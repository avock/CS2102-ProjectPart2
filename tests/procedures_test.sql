-- ALL PROCEDURE TESTS ARE INDEPENDENT OF EACH OTHER
-- useful commands
    -- delete all rows from tables
        TRUNCATE customers, employees, delivery_staff, delivery_requests, packages, accepted_requests, cancelled_or_unsuccessful_requests, cancelled_requests, unsuccessful_pickups, facilities, legs, unsuccessful_deliveries, return_legs, unsuccessful_return_deliveries CASCADE;
    -- restart serial ID for each table
        alter sequence customers_id_seq restart with 1;
        alter sequence delivery_requests_id_seq restart with 1;
        alter sequence employees_id_seq restart with 1;
        alter sequence facilities_id_seq restart with 1;

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
-- resubmit_requests
    INSERT INTO customers (name, gender, mobile) VALUES
     ('Chao Yung', 'male', '94235612'),
     ('Kevin Chang', 'male', '92354278'),
     ('Prittam Ravi', 'female', '82953156'),
     ('Shawn Kok', 'female', '82856178'),
     ('Jane Smith', 'female', '0987654321'),
     ('Bob Johnson', 'male', '1112223333');

     INSERT INTO employees (name, gender, dob, title, salary) VALUES
     ('John Doe', 'male', '1993-05-21', 'Manager', 6200.00),
     ('David Brown', 'male', '1980-01-01', 'Manager', 5000.00),
     ('Alice Koh', 'female', '1996-03-12', 'Intern', 1000.00),
     ('Beatrice Tan', 'female', '1994-09-05', 'Cleaner', 2200.00),
     ('Charlie Li', 'female', '1997-11-30', 'Customer Support', 3500.00),
     ('Mary Johnson', 'female', '1990-02-02', 'Coordinator', 3000.00),
     ('Tom Jones', 'male', '1985-03-03', 'Driver', 2000.00),
     ('Sarah Lee', 'female', '1995-04-04', 'Driver', 4000.00),
     ('Denzel Ong', 'male', '2000-01-24', 'Runner', 4200.00);

     INSERT INTO delivery_requests (customer_id, evaluater_id, status, pickup_addr, pickup_postal,
     recipient_name, recipient_addr, recipient_postal, submission_time, pickup_date,
     num_days_needed, price) VALUES (3, 1, 'submitted', '31 Summerfront Link', '685687', 'Jon Kit',
     '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39', '2022-05-07', 3, 5.00);

     INSERT INTO packages VALUES
     (1, 1, 10.0, 5.0, 5.0, 1.0, 'Book', 20.0, 10.0, 5.0, 5.0, 1.0),
     (1, 2, 20.0, 10.0, 10.0, 2.0, 'DVD', 30.0, 20.0, 10.0, 10.0, 2.0),
     (1, 3, 10, 20, 30, 2, 'T-shirt', 42.0, 10, 20, 30, 2),
     (1, 4, 5, 15, 25, 1.5, 'Coffee Mug', 15.0, 5, 15, 25, 1.5);

    -- after calling this, the delivery_request table should all be updated to request_id 2, eval_id 2, 
    --    submission_time 2022-01-01 12:00:00, pickupdate daysneeded price NULL, rest unchanged
    -- for packages, id++, all reported dimensions updates, content and value unchanged, actual dimensions all set to NULL
     CALL resubmit_request(1, 2, '2022-01-01 12:00:00', ARRAY[1,2,3,4], ARRAY[5,6,7,8], ARRAY[9,10,11,12], ARRAY[13,14,15,16])

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