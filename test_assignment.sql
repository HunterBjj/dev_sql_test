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

    IF OT FOUND OR _p_amount <= 0 THEN
      RAISE EXCEPTION 'Платеж % не должен быть меньши или равен нулю', p_payments_id;
    END IF;
    
    IF p_split_type = 0 THEN
      FOR _r IN (
         SELECT id_fb_bills, n_rest
         FROM dbo.fd_bills
         WHERE f_subscr = _p_subcr AND n_rest > 0
         ORDER BY d_date ASC, link ASC
      ) LOOP
          EXIT WHEN _p_mount <= 0;

          _pay_part := LEAST(_p_amount, r.n_rest);
          _p_amount := _p_amount - _pay_part;

          IF NOT FOUND OR _p_amount <= 0 OR _pay_part <= 0 THEN
            RAISE EXCEPTION 'Платеж не должен быть меньше или равен нулю. _p_amount = %, _pay_part = %', _p_amount, _pay_part;
          END IF;

          INSERT INTO dbo.fb_payment_details(id_f_payment, id_f_bill, n_anmount)
          VALUES(p_payment_id, _r.id_f_bill, _pay_part);

          UPDATE dbo.fb_bills
          SET n_rest = n_rest - _pay_part
          WHERE id_fb_bills = _r.id_fb_bills;
    END LOOP;

    ELSIF p_split_type = 1 THEN
      FOR _r IN ( 
          SELECT d_date
          FROM dbo.fd_bills
          WHERE f_subscr = _p_subscr AND n_rest > 0
          GROUP BY d_date
          ORDER BY d_date ASC
      ) LOOP
      EXIT WHEN _p_amount <= 0;

      -- Счетчик общего остатка на текущий месяц.
      SELECT SUM(n_rest) INTO _month_total_rest
      FROM dbo.fd_bills
      WHERE f_subscr = _p_subscr AND d_date = _r.d_date AND n_rest > 0;

      IF NOT FOUND OR _month_total_rest <= 0 THEN
            RAISE EXCEPTION 'Платеж не должен быть меньше или равен нулю. _month_total_rest = %', _month_total_rest;
      END IF;

      _month_total_pay := LEAST(_p_amount, _month_total_rest);

      -- Использую CTE, чтобы избежать накопления копеек из-за округления (остаток отдаем последней услуге).

      INSERT INTO dbo.fd_payment_details();
      WITH calc AS ()

    END IF;

  END;
EXCEPTION 
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Ошибка: % (Код: %)', SQLERRM, SQLSTATE;

END; 
$$
