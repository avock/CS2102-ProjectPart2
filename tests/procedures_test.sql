-- ALL PROCEDURE TESTS ARE INDEPENDENT OF EACH OTHER

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
-- insert_leg 
    INSERT INTO customers(name, gender, mobile)
    VALUES ('Jane Doe', 'female', '555-5555');

    INSERT INTO employees(name, gender, dob, title, salary)
    VALUES ('John Doe', 'male', '1990-01-01', 'Delivery Staff', 40000);

    INSERT INTO delivery_staff VALUES (1);

    INSERT INTO accepted_requests (id, card_number, payment_time, monitor_id)
    VALUES (1, '1234567890', '2023-04-13 10:30:00', 1);

    INSERT INTO facilities
    VALUES (1, '789 Elm St.', '54321');

    -- [OPTIONAL] can try inserting legs before to test
    INSERT INTO legs (request_id,leg_id,handler_id,start_time,end_time,destination_facility) 
    VALUES (1,1,1,'2023-04-12 16:00:00','2023-04-12 16:30:00',1);

    -- procedure call
    call insert_leg(1, 1, '2023-04-12 16:31:00', 1);