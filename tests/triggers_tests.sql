-- some useful queries
    alter sequence customers_id_seq restart with 1;
    alter sequence delivery_requests_id_seq restart with 1;
    alter sequence employees_id_seq restart with 1;
    alter sequence facilities_id_seq restart with 1;

-- delivery requests
    INSERT INTO customers(name, gender, mobile)
    VALUES ('Jane Doe', 'female', '555-5555');

    INSERT INTO employees(name, gender, dob, title, salary)
    VALUES ('John Doe', 'male', '1990-01-01', 'Delivery Staff', 40000);

    -- Insert a delivery request with no package, should prompt error
    INSERT INTO delivery_requests 
    VALUES (
    1,
    1,
    'submitted',
    '123 Main St.',
    '12345',
    'John Smith',
    '456 Elm St.',
    '67890',
    '2023-04-12 15:30:00'
    );

    -- inserts corrseponding package
    INSERT INTO packages (
    request_id,
    package_id,
    reported_height,
    reported_width,
    reported_depth,
    reported_weight,
    content,
    estimated_value
    ) VALUES (
    1,
    1,
    10,
    20,
    30,
    50,
    'Clothes',
    200
    );

-- packages
    -- same as before, but try using packages with non-consecutive package_id

-- unsuccesful pickups 
    -- part 1
        insert into delivery_staff 
            values (1);

        INSERT INTO accepted_requests (id, card_number, payment_time, monitor_id)
            VALUES (1, '1234-5678-9012-3456', '2023-04-12 16:00:00', 1);

        --  repeat this multiple times, then try using packages with non-consecutive package_ids
        INSERT INTO unsuccessful_pickups (
        request_id, 
        pickup_id, 
        handler_id, 
        pickup_time
        ) VALUES (
        1,
        1,
        1,
        '2023-04-12 15:35:00'
        );

    --  part 2
       -- just test using consecutive package_ids, but change the time to maybe a minute before    

    -- part 3
        -- create new delivery request and packages 
        INSERT INTO delivery_requests 
        VALUES (
        2,
        1,
        1,
        'submitted',
        '123 Main St.',
        '12345',
        'John Smith',
        '456 Elm St.',
        '67890',
        '2023-04-12 15:30:00'
        );

        INSERT INTO packages (
        request_id,
        package_id,
        reported_height,
        reported_width,
        reported_depth,
        reported_weight,
        content,
        estimated_value
        ) VALUES (
        2,
        1,
        10,
        20,
        30,
        50,
        'Clothes',
        200
        );

        INSERT INTO accepted_requests (id, card_number, payment_time, monitor_id)
            VALUES (2, '1234-5678-9012-3456', '2023-04-12 16:00:00', 1);    
        
        -- insert unsuccesul_pickup with timestamp before delivery_request
        INSERT INTO unsuccessful_pickups (
        request_id, 
        pickup_id, 
        handler_id, 
        pickup_time
        ) VALUES (
        2,
        1,
        1,
        '2023-04-12 15:29:00'
        );

-- legs
    -- Part 1
        -- test with not-starting from 0 and not consecutive integers, should work for both
        INSERT INTO facilities (id, address, postal)
            VALUES (1, '789 Elm St.', '54321');

        INSERT INTO legs (
        request_id,
        leg_id,
        handler_id,
        start_time,
        end_time,
        destination_facility
        ) VALUES (
        1,
        2,
        1,
        '2023-04-12 16:00:00',
        '2023-04-12 16:30:00',
        1
        );
    -- Part 2, 3
        -- change the start_time 
        -- for part2, start_time cannot be before submission_time for that request_id in delivery_requests
        -- for part3, start_time cannot be before pickup_time of the last unsuccesful_pickup for that req_id
        INSERT INTO legs (
        request_id,
        leg_id,
        handler_id,
        start_time,
        end_time,
        destination_facility
        ) VALUES (
        1,
        1,
        1,
        -- change here for part2, 3
        '2023-04-12 15:32:00',
        '2023-04-12 16:30:00',
        1
        );
    -- Part 4
        -- for part 1, try a start_time of leg(N) thats earlier than the end_time of leg(N-1)
        -- for part 2, try an end_time of leg(N-1) thats NULL, then try to insert leg(N)
        INSERT INTO legs (
        request_id,
        leg_id,
        handler_id,
        start_time,
        end_time,
        destination_facility
        ) VALUES (
        1,
        4,
        1,
        -- start_time
        '2023-04-12 15:35:00',
        -- end_time
        '2023-04-12 16:30:00',
        1
        );
-- unsuccessful deliveries
    -- part 1
        INSERT INTO unsuccessful_deliveries (request_id, leg_id, reason, attempt_time)
        -- should fail, as the timestamp is before the start_time of the corresponding leg 
        VALUES (1, 1, 'Wrong address', 
            -- change this part, the timestamp
            '2023-04-12 15:59:00');
    -- part 2
        -- insert an extra leg
            INSERT INTO legs (
            request_id,
            leg_id,
            handler_id,
            start_time,
            end_time,
            destination_facility
            ) VALUES (
            1,
            4,
            1,
            '2023-04-12 16:00:00',
            '2023-04-12 16:30:00',
            1
            );
        -- same as before, but try to include more than 3 
-- cancelled requests
    insert into cancelled_requests (id, cancel_time)
    values (1, 
    -- would fail here, as the timestamp is ≤ the subm_time
    '2023-04-12 15:30:00');
-- return legs 
    -- some initializations
        insert into cancelled_or_unsuccessful_requests
        values (1);

        INSERT INTO return_legs (request_id, leg_id, handler_id, start_time, source_facility)
        VALUES (1, 1, 1, '2023-04-12 15:30:00', 1);

        INSERT INTO return_legs (request_id, leg_id, handler_id, start_time, source_facility)
        VALUES (1, 2, 1, '2023-04-12 15:30:00', 1);
    -- part 1
        INSERT INTO return_legs (request_id, leg_id, handler_id, start_time, source_facility)
        VALUES (1, 
            -- 5 should fail as it is not consecutive
            5, 1, '2023-04-12 15:30:00', 1);

    -- part 2
        -- 2.1: no existing leg for delivery_request
            -- remove all legs from legs first
            -- then do : (should fail as there is no legs)
            INSERT INTO return_legs (request_id, leg_id, handler_id, start_time, source_facility)
            VALUES (1, 4, 1, 
            -- change the timestamp here, the previous return leg's end_time has to be inserted though, not NULL
            '2023-04-12 15:31:00', 1);
        -- 2.2: last leg end_time > return_leg start_time
            INSERT INTO return_legs (request_id, leg_id, handler_id, start_time, source_facility)
            VALUES (1, 1, 1, 
            '2023-04-12 16:31:00', 1);
        -- 2.3: return_leg's start_time has to be after cancel time
            -- remove all from legs and return_legs
            -- then:
            

    -- part 3
    
-- unsuccessful return deliveries
    INSERT INTO unsuccessful_return_deliveries (request_id, leg_id, reason, attempt_time)
    VALUES (1, 1, 'Delivery unsuccessful', 
        -- this part should fail as it's before the start_time of the return delivery
        '2023-04-12 15:29:00');