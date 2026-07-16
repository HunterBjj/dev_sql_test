/*
Требуется написать функцию dbo.ui_fp_payment_split, которая по внесенным платежам 
в таблицу dbo.fd_payments будет расщеплять его на оплаты по конкретным счетам и услугам исходя 
из заполненных строк в таблице **dbo.fd_bills**. 
*/

CREATE SCHEMA IF NOT EXISTS dbo;

CREATE TABLE IF NOT EXISTS dbo.fd_payment_details(
  id_fd_payment_details SERIAL PRIMARY KEY,
);

CREATE TABLE IF NOT EXISTS dbo.fd_payments (
  id_fd_payments SERIAL PRIMARY KEY,
  c_number,
  f_subscr INT NOT NULL,
  d_date DATE NOT NULL,
  n_amount NUMERIC(15,2)
);

CREATE TABLE IF NOT EXISTS dbo.fd_bills (
  id_fd_bills SERIAL PRIMARY KEY,
);


CREATE OR REPLACE FUNCTION dbo.ui_fp_payment_split(
    p_payment_id INT,
    p_split_type SMALL_INT
) 
RETURNS VOID AS $$
DECLARE

BEGIN
  IF EXISTS(SELECT 1 FROM dbo.fb_payement_details WHERE f_payment = p_payment_id)
    DELETE FROM dbo.fd_payment_details WHERE f_payment = p_payment_id;
  END IF;

END; 
$$
