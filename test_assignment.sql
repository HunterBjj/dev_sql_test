/*
Требуется написать функцию dbo.ui_fp_payment_split, которая по внесенным платежам 
в таблицу dbo.fd_payments будет расщеплять его на оплаты по конкретным счетам и услугам исходя 
из заполненных строк в таблице **dbo.fd_bills**. 
*/

CREATE SCHEMA IF NOT EXISTS dbo;

CREATE TABLE IF NOT EXISTS dbo.fd_payment_details(
  id_fd_payment_details  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,,
);

CREATE TABLE IF NOT EXISTS dbo.fd_payments (
  id_fd_payments INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  c_number VARCHAR(50),
  f_subscr INT NOT NULL,
  d_date DATE NOT NULL,
  n_amount NUMERIC(15,2)
);

CREATE TABLE IF NOT EXISTS dbo.fd_bills (
  id_fd_bills  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,,
);

CREATE OR REPLACE FUNCTION dbo.ui_fp_payment_split(
    p_payment_id INT,
    p_split_type SMALL_INT
) 
RETURNS VOID AS $$
DECLARE
  _p_subscr INT;
  _p_amount NUMERIC(15,2);
  _r RECORD;
  _pay_part NUMERIC(15,2);
  _month_total_rest NUMERIC(15,2);
  _month_total_pay NUMERIC(15,2);
BEGIN
  BEGIN
    PERFORM 1 
    FROM dbo.fd_payments 
    WHERE link = _link 
    FOR UPDATE;
    
    IF EXISTS(SELECT 1 FROM dbo.fb_payement_details WHERE f_payment = p_payment_id)
      UPDATE dbo.fd_bills b
      SET n_rest = b.n_rest + pd.n_amount
      FROM dbo.fd_payment_details pd
      WHERE pd.f_bill = b.link AND pd.f_payment = p_payment_id
      FOR UPDATE OF b; 
      
      DELETE FROM dbo.fd_payment_details WHERE f_payment = p_payment_id;
    END IF;

    SELECT f_subscr, n_amount
    INTO _p_subscr, _p_amount
    FROM dbo.fd_payments
    WHERE id_fd_payments = p_payments_id
    FOR UPDATE;

    IF _p_amount <= 0 THEN
      RAISE EXCEPTION 'Платеж % не должен быть меньши или равен нулю', p_payments_id;
    END IF;
    
    IF p_split_type = 0 THEN
      FOR _r IN (
         SELECT id_fb_bills, n_rest
      ) LOOP
          
    END IF;

    ELSIF p_split_type = 1 THEN
    END IF;

  END;
EXCEPTION 
    WHEN OTHERS THEN

END; 
$$
