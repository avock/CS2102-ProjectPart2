-- ALL FUNCTION TESTS ARE INDEPENDENT OF EACH OTHER
-- useful commands
    -- delete all rows from tables
        TRUNCATE customers, employees, delivery_staff, delivery_requests, packages, accepted_requests, cancelled_or_unsuccessful_requests, cancelled_requests, unsuccessful_pickups, facilities, legs, unsuccessful_deliveries, return_legs, unsuccessful_return_deliveries CASCADE;
    -- restart serial ID for each table
        alter sequence customers_id_seq restart with 1;
        alter sequence delivery_requests_id_seq restart with 1;
        alter sequence employees_id_seq restart with 1;
        alter sequence facilities_id_seq restart with 1;

-- view_trajectory

    INSERT INTO customers (name, gender, mobile) VALUES
     ('Chao Yung', 'male', '94235612'),
     ('Kevin Chang', 'male', '92354278'),
     ('Prittam Ravi', 'female', '82953156'),
     ('Shawn Kok', 'female', '82856178'),
     ('Jane Smith', 'female', '0987654321'),
     ('Bob Johnson', 'male', '1112223333');

    INSERT INTO employees(name, gender, dob, title, salary)
    VALUES ('John Doe', 'male', '1990-01-01', 'Delivery Staff', 40000);
    
    INSERT INTO delivery_requests (customer_id, evaluater_id, status, pickup_addr, pickup_postal, recipient_name, 
    recipient_addr, recipient_postal, submission_time, pickup_date, num_days_needed, price) VALUES 
    (1, 1, 'submitted', 'PICKUP ADDR', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (2, 1, 'submitted', 'PICKUP ADDR', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (3, 1, 'submitted', 'PICKUP ADDR', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (4, 1, 'submitted', 'PICKUP ADDR', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (5, 1, 'submitted', 'PICKUP ADDR', '685687','Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (6, 1, 'submitted', 'PICKUP ADDR', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00);

    INSERT INTO packages (
        request_id, package_id, reported_height, reported_width, reported_depth,
        reported_weight, content, estimated_value) VALUES (
        1, 1, 10, 20, 30,
        50, 'Clothes', 200);

    INSERT INTO facilities (id, address, postal) VALUES
    (1, '1F', '12345'),
    (2, '2F', '67890'),
    (3, '3F', '13579'),
    (4, '4F', '46801'),
    (5, '5F', '79135'),
    (6, '6F', '02468'),
    (7, '7F', '35791'),
    (8, '8F', '68013'),
    (9, '9F', '97531'),
    (10, '10F', '02468');

    INSERT INTO delivery_staff VALUES (1);

    INSERT INTO accepted_requests (id, card_number, payment_time, monitor_id) VALUES 
    (1, '1234567890', '2023-04-13 10:30:00', 1),
    (2, '1234567890', '2023-04-13 10:30:00', 1),
    (3, '1234567890', '2023-04-13 10:30:00', 1),
    (4, '1234567890', '2023-04-13 10:30:00', 1),
    (5, '1234567890', '2023-04-13 10:30:00', 1),
    (6, '1234567890', '2023-04-13 10:30:00', 1);

    INSERT INTO cancelled_or_unsuccessful_requests VALUES (4);

    INSERT INTO legs (request_id,leg_id,handler_id,start_time,end_time,destination_facility) VALUES 
    (1, 1, 1, '2023-04-12 16:00:00', '2023-04-12 16:00:01', 1) ,
    (1, 2, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:03', 1) ,
    (1, 3, 1, '2023-04-12 16:00:04', '2023-04-12 16:00:05', 1) ,
    (2, 4, 1, '2023-04-12 16:00:06', '2023-04-12 16:00:07', 9) ,
    (2, 5, 1, '2023-04-12 16:00:08', '2023-04-12 16:00:09', 8) ,
    (3, 6, 1, '2023-04-12 16:00:10', '2023-04-12 16:00:11', 2) ,
    (3, 7, 1, '2023-04-12 16:00:12', '2023-04-12 16:00:13', 9) ,
    (3, 8, 1, '2023-04-12 16:00:14', '2023-04-12 16:00:15', 4) ,
    (3, 9, 1, '2023-04-12 16:00:16', '2023-04-12 16:00:17', 10);

    INSERT INTO return_legs (request_id,leg_id,handler_id,start_time,end_time,source_facility) VALUES 
    (4, 1, 1, '2023-04-12 16:01:00', '2023-04-12 16:02:00', 8),
    (4, 2, 1, '2023-04-12 16:03:00', '2023-04-12 16:04:00', 1),
    (4, 3, 1, '2023-04-12 16:05:00', '2023-04-12 16:06:00', 2),
    (4, 4, 1, '2023-04-12 16:07:00', '2023-04-12 16:08:00', 1),
    (4, 5, 1, '2023-04-12 16:09:00', '2023-04-12 16:10:00', 2);

-- get_top_delivery_persons 

    INSERT INTO customers (name, gender, mobile) VALUES
     ('Chao Yung', 'male', '94235612'),
     ('Kevin Chang', 'male', '92354278'),
     ('Prittam Ravi', 'female', '82953156'),
     ('Shawn Kok', 'female', '82856178'),
     ('Jane Smith', 'female', '0987654321'),
     ('Bob Johnson', 'male', '1112223333');

    INSERT INTO facilities VALUES 
    (1, '789 Elm St.', '54321'),
    (2, '789 Elm St.', '54321'),
    (3, '789 Elm St.', '54321');

    INSERT INTO employees (name, gender, dob, title, salary) VALUES
    ('John Doe', 'male', '1993-05-21', 'Manager', 6200.00),
    ('David Brown', 'male', '1980-01-01', 'Manager', 5000.00),
    ('Alice Koh', 'female', '1996-03-12', 'Intern', 1000.00),
    ('Beatrice Tan', 'female', '1994-09-05', 'Cleaner', 2200.00),
    ('Charlie Li', 'female', '1997-11-30', 'Customer Support', 3500.00),
    ('Mary Johnson', 'female', '1990-02-02', 'Coordinator', 3000.00),
    ('Tom Jones', 'male', '1985-03-03', 'Driver', 2000.00),
    ('Sarah Lee', 'female', '1995-04-04', 'Driver', 4000.00),
    ('Denzel Ong', 'male', '2000-01-24', 'Runner', 4200.00),
    ('Denzel WANG', 'female', '2000-01-24', 'Runner', 4500.00);

    INSERT INTO delivery_requests (customer_id, evaluater_id, status, pickup_addr, pickup_postal, recipient_name, 
    recipient_addr, recipient_postal, submission_time, pickup_date, num_days_needed, price) VALUES 
    (1, 1, 'submitted', '31 Summerfront Link', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (2, 1, 'submitted', '31 Summerfront Link', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (3, 1, 'submitted', '31 Summerfront Link', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (4, 1, 'submitted', '31 Summerfront Link', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (5, 1, 'submitted', '31 Summerfront Link', '685687','Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00),
    (6, 1, 'submitted', '31 Summerfront Link', '685687', 'Jon Kit', 
    '23 Toa Payoh Drive', '434257', '2022-05-06 17:20:39',  '2022-05-07', 3, 5.00);

    INSERT INTO accepted_requests (id, card_number, payment_time, monitor_id) VALUES 
    (1, '1234567890', '2023-04-13 10:30:00', 1),
    (2, '1234567890', '2023-04-13 10:30:00', 1),
    (3, '1234567890', '2023-04-13 10:30:00', 1),
    (4, '1234567890', '2023-04-13 10:30:00', 1),
    (5, '1234567890', '2023-04-13 10:30:00', 1),
    (6, '1234567890', '2023-04-13 10:30:00', 1);

    INSERT INTO delivery_staff (id) VALUES (1), (2), (3), (4), (5), (6);

    INSERT INTO legs (request_id, leg_id, handler_id, start_time, end_time, destination_facility) VALUES 
    (1, 1, 1, '2023-04-12 16:00:00', '2023-04-12 16:20:00', 1),
    (1, 2, 2, '2023-04-12 16:30:00', '2023-04-12 16:40:00', 2),
    (1, 3, 3, '2023-04-12 16:50:00', '2023-04-12 17:00:00', 3);

    INSERT INTO cancelled_or_unsuccessful_requests (id) VALUES (2), (3), (4);

    INSERT INTO return_legs (request_id, leg_id, handler_id, start_time, source_facility) VALUES 
    (2, 1, 1, '2023-04-12 15:30:00', 1),
    (3, 1, 2, '2023-04-12 15:30:00', 1),
    (4, 1, 4, '2023-04-12 15:30:00', 1);

    INSERT INTO unsuccessful_pickups (request_id, pickup_id, handler_id, pickup_time) VALUES 
    (5, 1, 1, '2023-04-12 15:29:00'),
    (6, 2, 5, '2023-04-12 15:29:00');

    SELECT * FROM get_top_delivery_persons(6)

-- get_top_connections //TODO
