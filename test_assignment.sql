/*
  Требуется написать функцию dbo.ui_fp_payment_split, которая по внесенным платежам 
  в таблицу dbo.fd_payments будет расщеплять его на оплаты по конкретным счетам и услугам исходя 
  из заполненных строк в таблице **dbo.fd_bills**. 
  
  P.S. Сделал более читаемый код стайл.
*/

CREATE SCHEMA IF NOT EXISTS dbo;

CREATE TABLE IF NOT EXISTS dbo.fd_payment_details(
  id_fd_payment_details INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_f_bill INT,
  n_amount NUMERIC(15,2)
);

CREATE TABLE IF NOT EXISTS dbo.fd_payments (
  id_fd_payments INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  c_number VARCHAR(50),
  f_subscr INT NOT NULL,
  d_date DATE NOT NULL,
  n_amount NUMERIC(15,2)
);

CREATE TABLE IF NOT EXISTS dbo.fd_bills (
  id_fd_bills INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  n_rest NUMERIC(15,2) NOT NULL,
  d_date DATE NOT NULL,
  f_subscr INT NOT NULL,
  f_service INT,
  n_anmoun NUMERIC(15,2)
);

CREATE OR REPLACE FUNCTION dbo.ui_fp_payment_split(
    p_payment_id INT,
    p_split_type SMALLINT
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

    SELECT f_subscr, n_amount
    INTO _p_subscr, _p_amount
    FROM dbo.fd_payments
    WHERE id_fd_payments = p_payments_id
    FOR UPDATE;

    IF NOT FOUND OR _p_amount <= 0 THEN
      RAISE EXCEPTION 'Платеж % не должен быть меньши или равен нулю', p_payments_id;
    END IF;
    
    IF EXISTS(SELECT 1 FROM dbo.fb_payement_details WHERE id_fd_payments = p_payment_id)
      UPDATE dbo.fd_bills b
      SET n_rest = b.n_rest + pd.n_amount
      FROM dbo.fd_payment_details pd
      WHERE pd.f_bill = b.id_fb_bills AND pd.id_fd_payments = p_payment_id
      
      DELETE FROM dbo.fd_payment_details WHERE id_fd_payments = p_payment_id;
    END IF;
    
    IF p_split_type = 0 THEN
      FOR _r IN (
         SELECT id_fb_bills, n_rest
         FROM dbo.fd_bills
         WHERE f_subscr = _p_subcr AND n_rest > 0
         ORDER BY d_date ASC, id_fb_bills ASC
      ) LOOP
          EXIT WHEN _p_mount <= 0;

          _pay_part := LEAST(_p_amount, r.n_rest);
          _p_amount := _p_amount - _pay_part;

          IF NOT FOUND OR _p_amount <= 0 OR _pay_part <= 0 THEN
            RAISE EXCEPTION 'Платеж не должен быть меньше или равен нулю. _p_amount = %, _pay_part = %', _p_amount, _pay_part;
          END IF;

          INSERT INTO dbo.fb_payment_details(id_f_payment, id_f_bill, n_amount)
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
          ORDER BY d_date ASC, id_fb_bills ASC
      ) LOOP
      EXIT WHEN _p_amount <= 0;

      -- Счетчик общего остатка на текущий месяц.
      SELECT SUM(n_rest) INTO _month_total_rest
      FROM dbo.fd_bills
      WHERE f_subscr = _p_subscr AND d_date = _r.d_date AND n_rest > 0
      FOR UPDATE;

       CONTINUE WHEN _month_total_rest <= 0;

      _month_total_pay := LEAST(_p_amount, _month_total_rest);

      -- Использую CTE, чтобы избежать накопления копеек из-за округления (остаток отдаем последней услуге).
      INSERT INTO dbo.fd_payment_details(id_fd_payments, id_fd_bills, n_amount);

      WITH calc AS (
          SELECT 
              id_fd_bills,
              n_rest,
              FLOOR((n_rest / _month_total_rest) * _month_total_pay * 100) / 100 AS calc_pay,
              ROW_NUMBER() OVER (ORDER BY id_fd_bills DESC) as rn
          FROM dbo.fd_bills
          WHERE f_subscr = _p_subscr AND d_date = _r.d_date AND n_rest > 0
      ),
      adjusted AS (
          SELECT 
              id_fd_bills,
              CASE 
                  WHEN rn = 1 THEN _month_total_pay - COALESCE(
                      SUM(calc_pay) OVER (ORDER BY rn DESC ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 
                      0
                  )
                  ELSE calc_pay
              END AS final_pay
          FROM calc
      )
      
      SELECT p_payment_id, id_fd_bills, final_pay 
      FROM adjusted
      FOR UPDATE;

      _p_amount := _p_amount - _mounth_total_pay;
    END LOOP;
  END IF;
END;

EXCEPTION 
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Ошибка: % (Код: %)', SQLERRM, SQLSTATE;
END;
$$

-- Подготовка общих тестовых данных перед запуском тестов
TRUNCATE dbo.fd_bills, dbo.fd_payments, dbo.fd_payment_details RESTART IDENTITY;
INSERT INTO dbo.fd_bills (f_subscr, d_date, f_service, n_amount, n_rest) VALUES
(1, '2019-01-01', 10, 100.00, 100.00),
(1, '2019-01-01', 20, 150.00, 150.00),
(1, '2019-02-01', 10, 300.00, 300.00); -- Итого долг 550


/*
  Проверка №5: Платеж с переплатой (Сумма платежа 1000 при общем долге 550).
*/
BEGIN TRANSACTION;
    DO
    $$
    DECLARE _link INT;
    BEGIN
        -- Сбросим остатки в исходное состояние для чистоты теста внутри транзакции
        UPDATE dbo.fd_bills SET n_rest = n_amount WHERE f_subscr = 1;

        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-OVERPAY', 1, '20190105', 1000.00
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (_id_fd_payments := p_fd_payments_id, _n_type := 1::smallint);
    END;  
    $$;

    RAISE NOTICE '--- Результат проверки №5 (Переплата) ---';
    SELECT 'fd_bills (Должны быть в 0)' as tbl, d_date, f_service, n_amount, n_rest FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT 'fd_payment_details' as tbl, f_bill, n_amount FROM dbo.fd_payment_details;
ROLLBACK;

/*
  Проверка №6: Пропорциональный платеж, вызывающий неделимые копейки (Сумма 100.00 на долг 100 и 150)
  Пропорция 100/250 (40%) и 150/250 (60%) — ровные, возьмем сумму платежа 100.01 для проверки округлений.
*/
BEGIN TRANSACTION;
    DO
    $$
    DECLARE _link INT;
    BEGIN
        UPDATE dbo.fd_bills SET n_rest = n_amount WHERE f_subscr = 1;

        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-ROUND', 1, '20190105', 100.01
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (_id_fd_payments := p_fd_payments_id, _n_type := 1::smallint);
    END;
    $$;

    RAISE NOTICE '--- Результат проверки №6 (Округление копеек) ---';
    SELECT 'fd_bills' as tbl, d_date, f_service, n_amount, n_rest FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT 'fd_payment_details (Сумма должна быть строго 100.01)' as tbl, SUM(n_amount) FROM dbo.fd_payment_details;
ROLLBACK;


