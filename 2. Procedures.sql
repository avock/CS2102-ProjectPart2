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

-- resubmit_requests //TODO
-- insert_leg //TODO