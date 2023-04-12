-- submit requests 
    -- insert one dummy customer and employee
    INSERT INTO customers(name, gender, mobile)
    VALUES ('Jane Doe', 'female', '555-5555');

    INSERT INTO employees(name, gender, dob, title, salary)
    VALUES ('John Doe', 'male', '1990-01-01', 'Delivery Staff', 40000);

    -- procedure call
    CALL submit_request(
        1, 
        1, 
        '123 Main St.', 
        '12345', 
        'John Smith', 
        '456 Elm St.', 
        '67890', 
        '2023-04-12 15:30:00', 
        2, 
        ARRAY[10, 20], 
        ARRAY[5, 10], 
        ARRAY[5, 10], 
        ARRAY[2, 5], 
        ARRAY['Book', 'Clothing'], 
        ARRAY[50.00, 100.00]
    );
-- resubmit_requests //TODO
-- insert_leg //TODO