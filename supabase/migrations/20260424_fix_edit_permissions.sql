-- 🚀 FIX EDIT PERMISSIONS & STOCK DEDUCTION (V2)
-- This migration updates RLS policies to allow shop members to delete items during edits.
-- Fixed: Linked tables like sale_items and purchase_items need to join with parent tables to check shop_id.

-- 1. Update sale_items delete policy
DROP POLICY IF EXISTS "sale_items_delete_member" ON sale_items;
DROP POLICY IF EXISTS "sale_items_delete" ON sale_items;
DROP POLICY IF EXISTS "sale_items_delete_policy" ON sale_items;
CREATE POLICY "sale_items_delete_member" ON sale_items FOR DELETE TO authenticated USING (
    EXISTS (
        SELECT 1 FROM sales sa 
        JOIN shops s ON sa.shop_id = s.id 
        WHERE sa.id = sale_items.sale_id 
        AND (
            s.owner_user_id = auth.uid() 
            OR 
            EXISTS (SELECT 1 FROM shop_members sm WHERE sm.shop_id = s.id AND sm.user_id = auth.uid())
        )
    )
);

-- 2. Update purchase_items delete policy
DROP POLICY IF EXISTS "purchase_items_delete_member" ON purchase_items;
DROP POLICY IF EXISTS "purchase_items_delete" ON purchase_items;
DROP POLICY IF EXISTS "purchase_items_delete_policy" ON purchase_items;
CREATE POLICY "purchase_items_delete_member" ON purchase_items FOR DELETE TO authenticated USING (
    EXISTS (
        SELECT 1 FROM purchases pu 
        JOIN shops s ON pu.shop_id = s.id 
        WHERE pu.id = purchase_items.purchase_id 
        AND (
            s.owner_user_id = auth.uid() 
            OR 
            EXISTS (SELECT 1 FROM shop_members sm WHERE sm.shop_id = s.id AND sm.user_id = auth.uid())
        )
    )
);

-- 3. Update ledger_entries delete policy (ledger_entries HAS shop_id)
DROP POLICY IF EXISTS "ledger_entries_delete_member" ON ledger_entries;
DROP POLICY IF EXISTS "ledger_entries_delete" ON ledger_entries;
DROP POLICY IF EXISTS "ledger_entries_delete_policy" ON ledger_entries;
CREATE POLICY "ledger_entries_delete_member" ON ledger_entries FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM shops WHERE shops.id = ledger_entries.shop_id AND shops.owner_user_id = auth.uid())
    OR
    EXISTS (SELECT 1 FROM shop_members WHERE shop_members.shop_id = ledger_entries.shop_id AND shop_members.user_id = auth.uid())
);

-- 4. Update transactions delete policy (transactions HAS shop_id)
DROP POLICY IF EXISTS "transactions_delete_member" ON transactions;
DROP POLICY IF EXISTS "transactions_delete" ON transactions;
DROP POLICY IF EXISTS "transactions_delete_policy" ON transactions;
CREATE POLICY "transactions_delete_member" ON transactions FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM shops WHERE shops.id = transactions.shop_id AND shops.owner_user_id = auth.uid())
    OR
    EXISTS (SELECT 1 FROM shop_members WHERE shop_members.shop_id = transactions.shop_id AND shop_members.user_id = auth.uid())
);

-- 5. Update sales delete policy
DROP POLICY IF EXISTS "sales_delete_member" ON sales;
DROP POLICY IF EXISTS "sales_delete" ON sales;
DROP POLICY IF EXISTS "sales_delete_policy" ON sales;
CREATE POLICY "sales_delete_member" ON sales FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM shops WHERE shops.id = sales.shop_id AND shops.owner_user_id = auth.uid())
    OR
    EXISTS (SELECT 1 FROM shop_members WHERE shop_members.shop_id = sales.shop_id AND shop_members.user_id = auth.uid())
);

-- 6. Update purchases delete policy
DROP POLICY IF EXISTS "purchases_delete_member" ON purchases;
DROP POLICY IF EXISTS "purchases_delete" ON purchases;
DROP POLICY IF EXISTS "purchases_delete_policy" ON purchases;
CREATE POLICY "purchases_delete_member" ON purchases FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM shops WHERE shops.id = purchases.shop_id AND shops.owner_user_id = auth.uid())
    OR
    EXISTS (SELECT 1 FROM shop_members WHERE shop_members.shop_id = purchases.shop_id AND shop_members.user_id = auth.uid())
);
