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
    TRUNCATE customers, employees, delivery_staff, delivery_requests, packages, accepted_requests, cancelled_or_unsuccessful_requests, cancelled_requests, unsuccessful_pickups, facilities, legs, unsuccessful_deliveries, return_legs, unsuccessful_return_deliveries CASCADE;
    alter sequence customers_id_seq restart with 1;
    alter sequence delivery_requests_id_seq restart with 1;
    alter sequence employees_id_seq restart with 1;
    alter sequence facilities_id_seq restart with 1;

    DROP FUNCTION view_trajectory;

                CREATE OR REPLACE FUNCTION view_trajectory (request_id INTEGER)
                RETURNS TABLE (source_addr TEXT, destination_addr TEXT, start_time TIMESTAMP, end_time TIMESTAMP)
                AS $$
                BEGIN
                    RETURN QUERY 
                    WITH return_legs_path AS (
                        SELECT 
                        l1_f.address as source_addr,
                        COALESCE(l2_f.address, (SELECT pickup_addr FROM delivery_requests WHERE delivery_requests.id = view_trajectory.request_id)) as destination_addr,
                        l1.start_time,
                        l1.end_time
                        FROM return_legs as l1
                            LEFT OUTER JOIN return_legs as l2 ON l1.request_id = l2.request_id AND l1.leg_id = l2.leg_id - 1
                            FULL OUTER JOIN facilities as l2_f ON l2_f.id = l2.source_facility
                            FULL OUTER JOIN facilities as l1_f ON l1_f.id = l1.source_facility
                        WHERE l1.request_id = view_trajectory.request_id
                    ), legs_path AS (
                        SELECT
                        COALESCE(l1_f.address, (SELECT pickup_addr FROM delivery_requests WHERE delivery_requests.id = view_trajectory.request_id)) as source_addr,
                        COALESCE(l2_f.address, (SELECT recipient_addr FROM delivery_requests WHERE delivery_requests.id = view_trajectory.request_id)) as destination_addr,
                        l2.start_time,
                        l2.end_time
                        FROM legs as l1
                            FULL OUTER JOIN legs as l2 ON l1.request_id = l2.request_id AND l1.leg_id = l2.leg_id - 1
                            FULL OUTER JOIN facilities as l2_f ON l2_f.id = l2.destination_facility
                            FULL OUTER JOIN facilities as l1_f ON l1_f.id = l1.destination_facility
                        WHERE l2.request_id = view_trajectory.request_id
                    )
                    
                    (SELECT * 
                    FROM (
                        (SELECT * FROM legs_path) 
                        UNION 
                        (SELECT * FROM return_legs_path)) t 
                    ORDER BY start_time ASC);
                END
                $$ LANGUAGE plpgsql;

    INSERT INTO customers (name, gender, mobile) VALUES ('John Doe', 'male', '1234567890');
    INSERT INTO employees (name, gender, dob, title, salary) VALUES ('Jane Smith', 'female', '1990-01-01', 'Delivery Staff', 5000);
    INSERT INTO delivery_staff (id) VALUES (1);
    INSERT INTO delivery_requests (customer_id, evaluater_id, status, pickup_addr, pickup_postal, recipient_name, recipient_addr, recipient_postal, submission_time, pickup_date, num_days_needed, price)
    VALUES (1, 1, 'completed', 'A', '123456', 'Mary Johnson', 'B', '234567', '2023-04-01 09:00:00', '2023-04-01', 2, 50);
    INSERT INTO packages (request_id, package_id, reported_height, reported_width, reported_depth, reported_weight, content, estimated_value, actual_height, actual_width, actual_depth, actual_weight)
    VALUES (1, 1, 10, 20, 30, 5, 'Clothing', 100, 10, 20, 30, 5);
    INSERT INTO packages (request_id, package_id, reported_height, reported_width, reported_depth, reported_weight, content, estimated_value, actual_height, actual_width, actual_depth, actual_weight)
    VALUES (1, 2, 10, 20, 30, 5, 'Shoes', 50, 10, 20, 30, 5);
    INSERT INTO facilities (address, postal) VALUES ('AA', '123456');
    INSERT INTO facilities (address, postal) VALUES ('BB', '234567');
    INSERT INTO facilities (address, postal) VALUES ('CC', '345678');
    INSERT INTO accepted_requests (id, card_number, payment_time, monitor_id) VALUES (1, '1234-5678-9012-3456', '2023-04-04 10:00:00', 1);
    INSERT INTO legs (request_id, leg_id, handler_id, start_time, end_time, destination_facility) VALUES (1, 1, 1, '2023-04-01 10:00:00', '2023-04-01 11:00:00', 1);
    INSERT INTO legs (request_id, leg_id, handler_id, start_time, end_time, destination_facility) VALUES (1, 2, 1, '2023-04-02 09:00:00', '2023-04-02 10:00:00', 2);
    INSERT INTO legs (request_id, leg_id, handler_id, start_time, end_time, destination_facility) VALUES (1, 3, 1, '2023-04-03 10:00:00', '2023-04-03 11:00:00', 3);


    select * from view_trajectory(1)
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
