-- Migrasi 0011: Index performa untuk Anti-Cheat P2P Orders
CREATE INDEX IF NOT EXISTS idx_p2p_orders_seller_buyer
  ON public.p2p_orders (seller_id, buyer_id, status);
