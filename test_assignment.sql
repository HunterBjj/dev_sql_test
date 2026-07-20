/*
  Задание 1:
  Требуется написать функцию dbo.ui_fp_payment_split, которая по внесенным платежам 
  в таблицу dbo.fd_payments будет расщеплять его на оплаты по конкретным счетам и услугам исходя 
  из заполненных строк в таблице **dbo.fd_bills**. 
  
  P.S. Сделал более читаемый код стайл, изменил название переменных и входных параметрах.
*/

CREATE SCHEMA IF NOT EXISTS dbo;

CREATE TABLE IF NOT EXISTS dbo.fd_payments (
  id_fd_payments INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  c_number VARCHAR(50) NOT NULL,
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
  n_amount NUMERIC(15,2)
);

CREATE TABLE IF NOT EXISTS dbo.fd_payment_details(
  id_fd_payment_details INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_fd_bills INT NOT NULL,
  id_fd_payments INT NOT NULL,
  n_amount NUMERIC(15,2), 
  
  CONSTRAINT fk_details_payments 
    FOREIGN KEY (id_fd_payments) 
    REFERENCES dbo.fd_payments (id_fd_payments) 
    ON DELETE CASCADE,
    
  CONSTRAINT fk_id_f_bills 
    FOREIGN KEY (id_fd_bills) 
    REFERENCES dbo.fd_bills (id_fd_bills) 
    ON DELETE CASCADE
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
    WHERE id_fd_payments = p_payment_id
    FOR UPDATE;

    PERFORM 1 
    FROM dbo.fd_bills 
    WHERE f_subscr = _p_subscr 
    FOR UPDATE;
    
    IF EXISTS(SELECT 1 FROM dbo.fd_payment_details WHERE id_fd_payments = p_payment_id) THEN
      UPDATE dbo.fd_bills b
      SET n_rest = b.n_rest + pd.n_amount
      FROM dbo.fd_payment_details pd
      WHERE pd.id_fd_bills = b.id_fd_bills AND pd.id_fd_payments = p_payment_id;
      
      DELETE FROM dbo.fd_payment_details WHERE id_fd_payments = p_payment_id;
    END IF;
    
    IF p_split_type = 0 THEN
      FOR _r IN (
         SELECT id_fd_bills , n_rest
         FROM dbo.fd_bills
         WHERE f_subscr = _p_subscr AND n_rest > 0
         ORDER BY d_date ASC
      ) LOOP
          EXIT WHEN _p_amount <= 0;

          _pay_part := LEAST(_p_amount, _r.n_rest);
          _p_amount := _p_amount - _pay_part;

          INSERT INTO dbo.fd_payment_details(id_fd_payments , id_fd_bills, n_amount)
          VALUES(p_payment_id, _r.id_fd_bills, _pay_part);

          UPDATE dbo.fd_bills
          SET n_rest = n_rest - _pay_part
          WHERE id_fd_bills = _r.id_fd_bills;
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

       CONTINUE WHEN _month_total_rest <= 0;

      _month_total_pay := LEAST(_p_amount, _month_total_rest);

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
                      SUM(FLOOR((n_rest / _month_total_rest) * _month_total_pay * 100) / 100) 
                      OVER (ORDER BY rn DESC ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 
                      0
                  )
                  ELSE calc_pay
              END AS final_pay
          FROM calc
      ),
      inserted_rows AS (
          INSERT INTO dbo.fd_payment_details(id_fd_payments, id_fd_bills, n_amount)
          SELECT p_payment_id, id_fd_bills, final_pay 
          FROM adjusted
          RETURNING id_fd_bills, n_amount
      )

      UPDATE dbo.fd_bills b
      SET n_rest = b.n_rest - ins.n_amount
      FROM inserted_rows ins
      WHERE b.id_fd_bills = ins.id_fd_bills;

      _p_amount := _p_amount - _month_total_pay;
    END LOOP;
  END IF;
END;

EXCEPTION 
    WHEN OTHERS THEN
      RAISE EXCEPTION 'Ошибка: % (Код: %)', SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql;


TRUNCATE dbo.fd_bills, dbo.fd_payments, dbo.fd_payment_details RESTART IDENTITY;
INSERT INTO dbo.fd_bills (f_subscr, d_date, f_service, n_amount, n_rest) VALUES
(1, '2019-01-01', 10, 100.00, 100.00),
(1, '2019-01-01', 20, 150.00, 150.00),
(1, '2019-02-01', 10, 300.00, 300.00); -- Итого долг 550


--  Проверка №1: 
BEGIN TRANSACTION;
    DO
    $$
    DECLARE
        _id_fd_payments     INT;
    BEGIN
        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-123', 1, '20190105', 200
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 0::smallint);

        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-124', 1, '20190105', 220
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 0::smallint);

        RAISE NOTICE '--- Вызов проверки №1 успешно завершена---';
    END;
    $$;

    SELECT * FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT * FROM dbo.fd_payment_details;
ROLLBACK;


-- Проверка №2:
/*------------------------------------------------------------------------------------
    Пропорционально один платежа
-------------------------------------------------------------------------------------*/
BEGIN TRANSACTION;
    DO
    $$
    DECLARE
        _id_fd_payments     INT;
    BEGIN
        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-123', 1, '20190105', 200
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 1::smallint);

        RAISE NOTICE '--- Вызов проверки №2: Пропорционально один платежа успешно завершен ---';
    END;
    $$;

    SELECT * FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT * FROM dbo.fd_payment_details;
ROLLBACK;


-- Проверка №3:
/*------------------------------------------------------------------------------------
    Пропорционально два платежа
-------------------------------------------------------------------------------------*/
BEGIN TRANSACTION;
    DO
    $$
    DECLARE
        _id_fd_payments     INT;
    BEGIN
        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-123', 1, '20190105', 200
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 1::smallint);

        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-124', 1, '20190105', 220
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 1::smallint);

        RAISE NOTICE '--- Вызов проверки №3: Пропорционально два платежа успешно завершен ---';
    END;
    $$;

    SELECT * FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT * FROM dbo.fd_payment_details;   
ROLLBACK;


--  Проверка №4:
/*------------------------------------------------------------------------------------
    Один и тот же платеж 2 раза
-------------------------------------------------------------------------------------*/
BEGIN TRANSACTION;
    DO
    $$
    DECLARE
        _id_fd_payments     INT;
    BEGIN
        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-123', 1, '20190105', 200
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 1::smallint);

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 1::smallint);

         RAISE NOTICE '--- Вызов проверки №4: Один и тот же платеж 2 раза успешно завершен ---';
    END;
    $$;

    SELECT * FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT * FROM dbo.fd_payment_details;
ROLLBACK;


/*
  Задание 2:
  Написать еще 3-и проверки, для функции **dbo.ui_fp_payment_split** и объяснить почему выбрали именно эти тестовые случаи. 
  
  P.S. Выбрал тест с проверкой на округление, считаю, что проверка на точность необходимо для данной программе. Также надо проверить, когда просиходит переплата, 
  чтобы отработать это событие, так как вероятность этого намного выше, как и предыдущего.
*/

--  Проверка №5:
/*------------------------------------------------------------------------------------
    Платеж с переплатой (Сумма платежа 1000 при общем долге 550).
-------------------------------------------------------------------------------------*/
BEGIN TRANSACTION;
    DO
    $$
    DECLARE 
      _id_fd_payments INT;
    BEGIN
        UPDATE dbo.fd_bills SET n_rest = n_amount WHERE f_subscr = 1;

        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-OVERPAY', 1, '20190105', 1000.00
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 1::smallint);
        
        RAISE NOTICE '--- Вызов проверки №5: (Переплата) успешно завершен ---';
    END;  
    $$;

    SELECT * FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT * FROM dbo.fd_payment_details;   
ROLLBACK;


--  Проверка №6:
/*------------------------------------------------------------------------------------
    Пропорциональный платеж, вызывающий неделимые копейки (Сумма 100.01 на долг 100 и 150)
-------------------------------------------------------------------------------------*/
BEGIN TRANSACTION;
    DO
    $$
    DECLARE 
      _id_fd_payments INT;
    BEGIN
        UPDATE dbo.fd_bills SET n_rest = n_amount WHERE f_subscr = 1;

        INSERT INTO dbo.fd_payments (c_number, f_subscr, d_date, n_amount)
        SELECT 'П-ROUND', 1, '20190105', 100.01
        RETURNING id_fd_payments into _id_fd_payments;

        PERFORM dbo.ui_fp_payment_split (p_payment_id := _id_fd_payments, p_split_type := 1::smallint);
        
        RAISE NOTICE '--- Вызов проверки №6: (Округление копеек) успешно завершен ---';
    END;
    $$;

    SELECT * FROM dbo.fd_bills WHERE f_subscr = 1;
    SELECT * FROM dbo.fd_payment_details;   
ROLLBACK;





