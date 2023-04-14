-- submit requests 
    CREATE OR REPLACE PROCEDURE submit_request(
    customer_id INTEGER, evaluator_id INTEGER, 
    pickup_addr TEXT, pickup_postal TEXT, 
    recipient_name TEXT, recipient_addr TEXT, 
    recipient_postal TEXT, submission_time TIMESTAMP, 
    package_num INTEGER, reported_height INTEGER[], 
    reported_width INTEGER[], reported_depth INTEGER[], 
    reported_weight INTEGER[], content TEXT[], 
    estimated_value NUMERIC[]
    ) AS $$ 
    
    DECLARE 
        curr_request_id INTEGER;
        package_id INTEGER;
    BEGIN 
        -- Insert delivery request
        INSERT INTO delivery_requests (
            customer_id, evaluater_id, status, 
            pickup_addr, pickup_postal, recipient_name, 
            recipient_addr, recipient_postal, 
            submission_time) 
        VALUES (
            customer_id, evaluator_id, 'submitted', 
            pickup_addr, pickup_postal, recipient_name, 
            recipient_addr, recipient_postal, 
            submission_time
        ) RETURNING id INTO curr_request_id;

        -- Insert packages for the delivery request
        FOR i IN 1..package_num LOOP 
            INSERT INTO packages (
                request_id, package_id, reported_height, 
                reported_width, reported_depth, 
                reported_weight, content, estimated_value) 
            VALUES (
                curr_request_id, i, reported_height[i], 
                reported_width[i], reported_depth[i], 
                reported_weight[i], content[i], 
                estimated_value[i]);
        END LOOP;

        -- Set actual dimensions to NULL for each package
        UPDATE packages 
        SET 
            actual_height = NULL, 
            actual_width = NULL, 
            actual_depth = NULL, 
            actual_weight = NULL 
        WHERE 
            packages.request_id = curr_request_id;

        -- Set pickup_date, num_days_needed, and price to NULL for the delivery request
        UPDATE delivery_requests 
        SET 
            pickup_date = NULL, 
            num_days_needed = NULL, 
            price = NULL 
        WHERE 
            id = curr_request_id;
    END;
    $$ LANGUAGE plpgsql;

-- resubmit_requests 
    CREATE OR REPLACE PROCEDURE resubmit_request(request_id INTEGER, evaluator_id INTEGER, submission_time TIMESTAMP, reported_height INTEGER[] , reported_width INTEGER[], reported_depth INTEGER[], reported_weight INTEGER[])
    AS $$
    DECLARE
        count INTEGER;
        r_id INTEGER;
        cus_id INTEGER;
        pu_addr TEXT;
        pu_postal TEXT;
        reci_name TEXT;
        reci_addr TEXT;
        reci_postal TEXT;
        con TEXT;
        est_value NUMERIC;
    BEGIN
        SELECT customer_id, pickup_addr, pickup_postal, recipient_name, recipient_addr, recipient_postal INTO cus_id, pu_addr, pu_postal, reci_name, reci_addr, reci_postal
        FROM delivery_requests
        WHERE delivery_requests.id = resubmit_request.request_id;

        SELECT COUNT(*) INTO count
        FROM packages
        WHERE packages.request_id = resubmit_request.request_id;

        INSERT INTO delivery_requests (customer_id, evaluater_id, status, pickup_addr, pickup_postal, recipient_name, recipient_addr, recipient_postal, submission_time)
        VALUES (cus_id, evaluator_id, 'submitted', pu_addr, pu_postal, reci_name, reci_addr, reci_postal, submission_time) 
        RETURNING id INTO r_id;

        FOR i IN 1..count LOOP
            UPDATE packages as p
            SET request_id = r_id,
                reported_height = resubmit_request.reported_height[i],
                reported_width = resubmit_request.reported_width[i],
                reported_depth = resubmit_request.reported_depth[i],
                reported_weight = resubmit_request.reported_weight[i],
                actual_height = NULL,
                actual_width = NULL,
                actual_depth = NULL,
                actual_weight = NULL
            WHERE p.request_id = resubmit_request.request_id AND p.package_id = i;
        END LOOP;

        -- Set pickup_date, num_days_needed, and price to NULL for the delivery request
        UPDATE delivery_requests
        SET pickup_date = NULL, num_days_needed = NULL, price = NULL
        WHERE id = r_id;

        END;
    $$ LANGUAGE plpgsql;

-- insert_leg 
    CREATE OR REPLACE PROCEDURE insert_leg(request_id INTEGER, handler_id INTEGER, start_time TIMESTAMP, destination_facility INTEGER) AS $$
    DECLARE
        curr_leg_id INTEGER;
    BEGIN
        SELECT COALESCE(MAX(legs.leg_id), 0) + 1 INTO curr_leg_id 
        FROM legs 
        WHERE legs.request_id = insert_leg.request_id;

        INSERT INTO legs (request_id, leg_id, handler_id, start_time, destination_facility, end_time)
        VALUES (request_id, curr_leg_id, handler_id, start_time, destination_facility, NULL);
    END;
    $$ LANGUAGE plpgsql;
