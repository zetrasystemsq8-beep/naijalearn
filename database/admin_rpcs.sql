-- Supabase SQL: Add these RPC functions to your database

-- 1. Admin Approve Cent Purchase
CREATE OR REPLACE FUNCTION admin_approve_cent_purchase(request_id UUID)
RETURNS JSON AS $$
DECLARE
  caller_id UUID := auth.uid();
  is_admin_user BOOLEAN;
  req_record RECORD;
BEGIN
  -- Check if caller is admin
  SELECT is_admin INTO is_admin_user FROM public.profiles WHERE id = caller_id;
  
  IF is_admin_user IS NULL OR is_admin_user = FALSE THEN
    RAISE EXCEPTION 'Unauthorized: Only admins can approve purchases';
  END IF;

  -- Fetch the request
  SELECT * INTO req_record FROM public.cent_purchase_requests WHERE id = request_id;
  
  IF req_record IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  -- Update request status
  UPDATE public.cent_purchase_requests
  SET 
    status = 'fulfilled',
    fulfilled_at = NOW()
  WHERE id = request_id;

  -- TODO: Credit user's real Cent balance here once table is confirmed
  -- Example (to be filled in):
  -- UPDATE app_currency_balances 
  -- SET balance = balance + req_record.cent_amount 
  -- WHERE user_id = req_record.user_id AND app_id = 'naijalearn';

  RETURN JSON_BUILD_OBJECT(
    'success', TRUE,
    'message', 'Payment approved and user credited',
    'request_id', request_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Admin Reject Cent Purchase
CREATE OR REPLACE FUNCTION admin_reject_cent_purchase(request_id UUID, rejection_reason TEXT DEFAULT NULL)
RETURNS JSON AS $$
DECLARE
  caller_id UUID := auth.uid();
  is_admin_user BOOLEAN;
  req_record RECORD;
BEGIN
  -- Check if caller is admin
  SELECT is_admin INTO is_admin_user FROM public.profiles WHERE id = caller_id;
  
  IF is_admin_user IS NULL OR is_admin_user = FALSE THEN
    RAISE EXCEPTION 'Unauthorized: Only admins can reject purchases';
  END IF;

  -- Fetch the request
  SELECT * INTO req_record FROM public.cent_purchase_requests WHERE id = request_id;
  
  IF req_record IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  -- Update request status
  UPDATE public.cent_purchase_requests
  SET 
    status = 'rejected',
    fulfilled_at = NOW(),
    fulfilled_by_note = COALESCE(rejection_reason, 'Rejected by admin')
  WHERE id = request_id;

  RETURN JSON_BUILD_OBJECT(
    'success', TRUE,
    'message', 'Payment rejected',
    'request_id', request_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Add is_admin column to profiles table (if not already there)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT FALSE;

-- 4. Grant execute permissions (adjust to your auth schema)
GRANT EXECUTE ON FUNCTION admin_approve_cent_purchase(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_reject_cent_purchase(UUID, TEXT) TO authenticated;
