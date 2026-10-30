CREATE TABLE customer (
    id NUMBER PRIMARY KEY,
    name VARCHAR2(100)
);

CREATE OR REPLACE PROCEDURE update_customer (
    p_id IN customer.id%TYPE,
    p_name IN customer.name%TYPE
) AS
BEGIN
    UPDATE customer
       SET name = p_name
     WHERE id = p_id;
END;
/
