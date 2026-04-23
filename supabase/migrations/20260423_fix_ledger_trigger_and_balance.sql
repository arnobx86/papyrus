-- 🚀 Fix Ledger Entry Trigger for Party Balance Integrity
-- This migration updates the party balance trigger to correctly distinguish between
-- Debts (Due/Loan) and Payments (Payment/Received) based on notes prefixes.
-- It also adds support for UPDATE operations and recalibrates all party balances.

CREATE OR REPLACE FUNCTION handle_party_balance_operation()
RETURNS TRIGGER AS $$
DECLARE
    v_amount NUMERIC;
    v_type TEXT;
    v_notes TEXT;
    v_party_id UUID;
    v_multiplier INTEGER;
BEGIN
    -- 1. Handle OLD row (reverse previous balance impact)
    IF (TG_OP IN ('DELETE', 'UPDATE')) THEN
        v_amount := OLD.amount;
        v_type := OLD.type;
        v_notes := COALESCE(OLD.notes, '');
        v_party_id := OLD.party_id;
        
        -- Logic matching Flutter retrieval logic:
        -- Positive multiplier increases net balance (more receivable/less payable)
        -- Negative multiplier decreases net balance (more payable/less receivable)
        IF (v_type = 'loan' OR v_type = 'payment_made') THEN
            -- 'loan' is usually Receivable (Money owed to us)
            -- But if it has 'Received:' it's a payment from customer (decreases receivable)
            IF (v_notes ILIKE 'Received:%' OR v_notes ILIKE 'Loan Received%') THEN
                v_multiplier := -1; -- Received payment decreases net balance
            ELSE
                v_multiplier := 1;  -- Basic loan increases net balance
            END IF;
        ELSIF (v_type = 'due' OR v_type = 'payment_received') THEN
            -- 'due' is usually Payable (Money we owe)
            -- But if it has 'Payment:' it's a payment we made (decreases payable)
            IF (v_notes ILIKE 'Payment:%' OR v_notes ILIKE 'Due Payment%') THEN
                v_multiplier := 1;  -- Making a payment increases net balance
            ELSE
                v_multiplier := -1; -- Basic due decreases net balance
            END IF;
        ELSE
            -- Unknown types for now default to no impact
            v_multiplier := 0;
        END IF;
        
        UPDATE parties SET balance = balance - (v_amount * v_multiplier) WHERE id = v_party_id;
    END IF;

    -- 2. Handle NEW row (apply new balance impact)
    IF (TG_OP IN ('INSERT', 'UPDATE')) THEN
        v_amount := NEW.amount;
        v_type := NEW.type;
        v_notes := COALESCE(NEW.notes, '');
        v_party_id := NEW.party_id;
        
        IF (v_type = 'loan' OR v_type = 'payment_made') THEN
            IF (v_notes ILIKE 'Received:%' OR v_notes ILIKE 'Loan Received%') THEN
                v_multiplier := -1;
            ELSE
                v_multiplier := 1;
            END IF;
        ELSIF (v_type = 'due' OR v_type = 'payment_received') THEN
            IF (v_notes ILIKE 'Payment:%' OR v_notes ILIKE 'Due Payment%') THEN
                v_multiplier := 1;
            ELSE
                v_multiplier := -1;
            END IF;
        ELSE
            v_multiplier := 0;
        END IF;
        
        UPDATE parties SET balance = balance + (v_amount * v_multiplier) WHERE id = v_party_id;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-create trigger with UPDATE support
DROP TRIGGER IF EXISTS trg_party_balance ON ledger_entries;
CREATE TRIGGER trg_party_balance 
AFTER INSERT OR DELETE OR UPDATE ON ledger_entries 
FOR EACH ROW EXECUTE FUNCTION handle_party_balance_operation();

-- 🛠️ RECALIBRATION: Sync all party balances from ledger_entries
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM parties LOOP
        UPDATE parties p
        SET balance = (
            SELECT COALESCE(SUM(
                CASE 
                    WHEN l.type IN ('loan', 'payment_made') THEN
                        CASE WHEN (COALESCE(l.notes, '') ILIKE 'Received:%' OR COALESCE(l.notes, '') ILIKE 'Loan Received%') THEN -l.amount ELSE l.amount END
                    WHEN l.type IN ('due', 'payment_received') THEN
                        CASE WHEN (COALESCE(l.notes, '') ILIKE 'Payment:%' OR COALESCE(l.notes, '') ILIKE 'Due Payment%') THEN l.amount ELSE -l.amount END
                    ELSE 0
                END
            ), 0)
            FROM ledger_entries l
            WHERE l.party_id = r.id
        )
        WHERE p.id = r.id;
    END LOOP;
END $$;
