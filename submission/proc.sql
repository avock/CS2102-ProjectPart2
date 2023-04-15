-- triggers
    -- delivery requests
        CREATE OR REPLACE FUNCTION check_delivery_requests()
        RETURNS TRIGGER AS $$
        BEGIN
        IF NOT EXISTS (SELECT 1 FROM packages WHERE request_id = NEW.id) THEN
            RAISE EXCEPTION 'Each delivery request must have at least one package.';
        END IF;
        RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE CONSTRAINT TRIGGER delivery_requests
        AFTER INSERT ON delivery_requests
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW
        EXECUTE FUNCTION check_delivery_requests();

    -- package
        CREATE OR REPLACE FUNCTION check_delivery_request_packages()
        RETURNS TRIGGER AS $$
        DECLARE
            last_package_id INTEGER;
        BEGIN
            SELECT MAX(package_id) INTO last_package_id
            FROM packages 
            WHERE request_id = NEW.request_id;
            
            IF (last_package_id IS NULL) AND (NEW.package_id != 1) THEN
                RAISE EXCEPTION 'Package IDs for delivery request % must start from 1.', NEW.request_id;
            END IF;
            IF (last_package_id IS NOT NULL) AND (last_package_id != NEW.package_id - 1) THEN
                RAISE EXCEPTION 'Package IDs for delivery request % must be consecutive integers. The latest packages ID for this delivery request is %', NEW.request_id, last_package_id;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER delivery_request_packages
        BEFORE INSERT ON packages
        FOR EACH ROW
        EXECUTE FUNCTION check_delivery_request_packages();

    -- unsuccesful pickups
        CREATE OR REPLACE FUNCTION check_unsuccessful_pickups()
        RETURNS TRIGGER AS $$
        DECLARE
            last_pickup_id INTEGER;
            last_pickup_time TIMESTAMP;
        BEGIN
            SELECT MAX(pickup_id), MAX(pickup_time) INTO last_pickup_id, last_pickup_time
            FROM unsuccessful_pickups
            WHERE request_id = NEW.request_id;
            
            -- Check if pickup ID starts from 1
            IF (last_pickup_id IS NULL) AND (NEW.pickup_id != 1) THEN
                RAISE EXCEPTION 'Unsuccessful pickup IDs for delivery request % must start from 1.', NEW.request_id;
            END IF;
            
            -- Check if the current pickup ID is consecutive
            IF (last_pickup_id IS NOT NULL) AND (last_pickup_id != NEW.pickup_id - 1) THEN
                RAISE EXCEPTION 'Unsuccessful pickup IDs for delivery request % must be consecutive integers.', NEW.request_id;
            END IF;


            -- Check if the current pickup timestamp is after the submission_time of the corresponding delivery request
            IF NEW.pickup_time <= (SELECT submission_time FROM delivery_requests WHERE id = NEW.request_id) THEN
                RAISE EXCEPTION 'Unsuccessful pickup timestamps for delivery request % must be after the submission time of the corresponding delivery request.', NEW.request_id;
            END IF;

            -- Check if the current pickup timestamp is after the previous pickup timestamp (if any)
            IF (last_pickup_time IS NOT NULL) AND (last_pickup_time <= NEW.pickup_time) THEN
                RAISE EXCEPTION 'Unsuccessful pickup timestamps for delivery request % must be after the previous one.', NEW.request_id;
            END IF;

            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER unsuccessful_pickups
        BEFORE INSERT ON unsuccessful_pickups
        FOR EACH ROW
        EXECUTE FUNCTION check_unsuccessful_pickups();

    -- legs
        -- Part 1
            CREATE OR REPLACE FUNCTION check_leg_id()
            RETURNS TRIGGER AS $$
            DECLARE
                last_leg_id INTEGER;
            BEGIN
                SELECT MAX(leg_id) INTO last_leg_id FROM legs WHERE request_id = NEW.request_id;

                IF (last_leg_id IS NULL) AND (NEW.leg_id != 1) THEN
                    RAISE EXCEPTION 'Leg IDs for delivery request % must start from 1.', NEW.request_id;
                END IF;
                
                IF (last_leg_id IS NOT NULL) AND (last_leg_id != NEW.leg_id - 1) THEN
                    RAISE EXCEPTION 'Leg IDs for delivery request % must be consecutive integers.', NEW.request_id;
                END IF;
                
            RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER leg_id
            BEFORE INSERT ON legs
            FOR EACH ROW
            EXECUTE FUNCTION check_leg_id();

        -- Part 2
            CREATE OR REPLACE FUNCTION check_first_leg_start_time1()
            RETURNS TRIGGER AS $$
            DECLARE
            subm_time TIMESTAMP;
            BEGIN
                SELECT submission_time INTO subm_time FROM delivery_requests 
                    WHERE (id = NEW.request_id);
                
                IF (NEW.leg_id = 1) THEN
                    IF (NEW.start_time <= subm_time) THEN
                        RAISE EXCEPTION 'Invalid start time for first leg, start_time of first leg must be after the time the delivery request was placed';
                    END IF;
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER first_leg_start_time1
            AFTER INSERT ON legs
            FOR EACH ROW
            EXECUTE FUNCTION check_first_leg_start_time1();

        -- Part 3
            CREATE OR REPLACE FUNCTION check_first_leg_start_time2()
            RETURNS TRIGGER AS $$
            DECLARE
                last_unsuccessful_pickup_time TIMESTAMP;
            BEGIN
                SELECT MAX(pickup_time) INTO last_unsuccessful_pickup_time FROM unsuccessful_pickups WHERE request_id = NEW.request_id;
                IF (NEW.leg_id = 1) THEN
                    IF (last_unsuccessful_pickup_time IS NOT NULL) AND (NEW.start_time < last_unsuccessful_pickup_time) THEN
                        RAISE EXCEPTION 'Invalid start time for first leg, start_time of first leg cannot be before last unsuccessful pickup time';
                    END IF;
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER first_leg_start_time2
            AFTER INSERT ON legs
            FOR EACH ROW
            EXECUTE FUNCTION check_first_leg_start_time2();

        -- Part 4
            CREATE OR REPLACE FUNCTION check_leg_start_and_end_time()
            RETURNS TRIGGER AS $$
            DECLARE
                last_leg_end_time TIMESTAMP;
            BEGIN
                SELECT end_time INTO last_leg_end_time FROM legs WHERE request_id = NEW.request_id AND leg_id = NEW.leg_id - 1;
                
                IF (NEW.leg_id > 1) AND (last_leg_end_time IS NULL) THEN
                    RAISE EXCEPTION 'Invalid leg, end time of previous leg must not be NULL';
                END IF;
                IF (NEW.leg_id > 1) AND (NEW.start_time <= last_leg_end_time) THEN
                    RAISE EXCEPTION 'Invalid start time for leg, must not be before end time of previous leg';
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER leg_start_and_end_time
            AFTER INSERT ON legs
            FOR EACH ROW
            EXECUTE FUNCTION check_leg_start_and_end_time();

    -- unsuccessful deliveries
        CREATE OR REPLACE FUNCTION check_unsuccessful_deliveries()
        RETURNS TRIGGER AS $$
        DECLARE 
            curr_start_time TIMESTAMP;
            unsuccessful_time TIMESTAMP;
            unsuccessful_count INTEGER;
        BEGIN
            -- Get the start time of the corresponding leg
            SELECT start_time INTO curr_start_time
            FROM legs
            WHERE request_id = NEW.request_id AND leg_id = NEW.leg_id;

            -- Constraint 8: Check if the unsuccessful delivery timestamp is after the start time
            IF NEW.attempt_time < curr_start_time THEN
                RAISE EXCEPTION 'The timestamp of unsuccessful_delivery for delivery_requst % should be after the start_time of the corresponding leg.', NEW.request_id;
            END IF;

            -- Count the number of unsuccessful deliveries for the request
            SELECT COUNT(*) INTO unsuccessful_count
            FROM unsuccessful_deliveries
            WHERE request_id = NEW.request_id;

            -- Constraint 9: Check if there are more than three unsuccessful deliveries for the request
            IF unsuccessful_count >= 3 THEN
                RAISE EXCEPTION 'For delivery request ID=%, there is currently % unsuccesful deliveries. There can be at most 3 unsuccessful_deliveries for each delivery_request.', NEW.request_id, unsuccessful_count;
            END IF;

            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER unsuccessful_deliveries
        BEFORE INSERT ON unsuccessful_deliveries
        FOR EACH ROW
        EXECUTE FUNCTION check_unsuccessful_deliveries();

    -- cancelled requests
        CREATE OR REPLACE FUNCTION check_cancelled_requests()
        RETURNS TRIGGER AS $$
        DECLARE
            sub_time TIMESTAMP;
        BEGIN
            SELECT submission_time INTO sub_time
            FROM delivery_requests
            WHERE delivery_requests.id = NEW.id;
            IF (sub_time IS NOT NULL) AND (sub_time >= NEW.cancel_time) THEN
                RAISE EXCEPTION 'For request ID=%, the cancel_time should be after the submission_time of the corresponding delivery request.', NEW.id;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER cancelled_requests
        BEFORE INSERT ON cancelled_requests
        FOR EACH ROW
        EXECUTE FUNCTION check_cancelled_requests();

    -- return legs 
        -- trigger 11
            CREATE OR REPLACE FUNCTION check_return_leg_id()
            RETURNS TRIGGER AS $$
            DECLARE 
                max_return_leg_id INTEGER;
            BEGIN
                SELECT MAX(leg_id) INTO max_return_leg_id
                FROM return_legs
                WHERE return_legs.request_id = NEW.request_id;

                IF max_return_leg_id IS NULL THEN
                    IF NEW.leg_id <> 1 THEN
                        RAISE EXCEPTION 'First return_leg ID must be 1';
                    END IF;
                END IF;

                IF max_return_leg_id IS NOT NULL THEN
                    IF NEW.leg_id <> (max_return_leg_id + 1) THEN
                        RAISE EXCEPTION 'Every new return_leg ID has to be exactly one more than the previous one, the latest return_leg ID for delivery_request ID=% is %', NEW.request_id, max_return_leg_id;
                    END IF;
                END IF;

                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER return_leg_id
            BEFORE INSERT ON return_legs
            FOR EACH ROW
            EXECUTE FUNCTION check_return_leg_id();

        -- trigger 12
            CREATE OR REPLACE FUNCTION check_consistency_return_legs_insertion()
            RETURNS TRIGGER AS $$
            DECLARE 
                existing_request_id INTEGER;
                last_existing_leg_end_time TIMESTAMP;
                existing_leg_id INTEGER;
                existing_cancel_time TIMESTAMP;
            BEGIN

                -- There are no existing legs for this delivery_request_ID
                SELECT request_id INTO existing_request_id 
                FROM legs 
                WHERE legs.request_id = NEW.request_id;
                
                IF existing_request_id IS NULL THEN
                    RAISE EXCEPTION 'There is no existing leg for delivery request ID=%', NEW.request_ID;
                END IF;

                -- Last existing leg’s end_time should not be after the start_time of the return_leg
                SELECT end_time INTO last_existing_leg_end_time 
                FROM legs
                WHERE request_id = NEW.request_id
                ORDER BY leg_id DESC LIMIT 1;
                
                IF (last_existing_leg_end_time IS NOT NULL) AND (NEW.start_time <= last_existing_leg_end_time) THEN
                    RAISE EXCEPTION 'The start_time of a return leg cannot be earlier than the end_time of the last leg.';
                END IF;		

                -- The return_leg’s start_time should be after the cancel_time of the request (if any).
                SELECT cancel_time INTO existing_cancel_time
                FROM cancelled_requests
                WHERE cancelled_requests.id = NEW.request_id;

                IF existing_cancel_time IS NOT NULL THEN
                    IF NEW.start_time <= existing_cancel_time THEN
                        RAISE EXCEPTION 'The start_time of a return_leg must be after the cancel time of the delivery request with ID=%', NEW.request_ID;
                    END IF;
                END IF;

                RETURN NEW;

            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER consistency_return_legs_insertion
            BEFORE INSERT ON return_legs
            FOR EACH ROW
            EXECUTE FUNCTION check_consistency_return_legs_insertion();

        -- trigger 13
            CREATE OR REPLACE FUNCTION check_at_most_three_unsuccessful_return_deliveries()
            RETURNS TRIGGER AS $$
            DECLARE 
                unsuccessful_count INTEGER;
            BEGIN
            -- Count the number of unsuccessful deliveries for the request
                SELECT COUNT(*) INTO unsuccessful_count
                FROM unsuccessful_return_deliveries
                WHERE unsuccessful_return_deliveries.request_id = NEW.request_id;

                IF unsuccessful_count >= 3 THEN
                    RAISE EXCEPTION 'For delivery request ID=%, there can be at most 3 unsuccessful_return_deliveries.', NEW.request_id;
                END IF;
                RETURN NEW;

            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER at_most_three_unsuccessful_return_deliveries
            BEFORE INSERT ON return_legs
            FOR EACH ROW
            EXECUTE FUNCTION check_at_most_three_unsuccessful_return_deliveries();

    -- unsuccessful return deliveries
        CREATE OR REPLACE FUNCTION check_unsuccessful_return_deliveries()
        RETURNS TRIGGER AS $$
        DECLARE
            s_time TIMESTAMP;
        BEGIN
            SELECT start_time INTO s_time
            FROM return_legs
            WHERE return_legs.request_id = NEW.request_id;
            
            IF (s_time IS NOT NULL) AND (s_time >= NEW.attempt_time) THEN
                RAISE EXCEPTION 'For unsuccessful_return_deliveries ID=%, the attempt_time should be after the start_time of corresponding return_leg.', NEW.request_id;
            END IF;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER unsuccessful_return_deliveries
        BEFORE INSERT ON unsuccessful_return_deliveries
        FOR EACH ROW
        EXECUTE FUNCTION check_unsuccessful_return_deliveries();

-- Routines
    -- Procedures
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
                    INSERT INTO packages (request_id, package_id, reported_height, reported_width, reported_depth, reported_weight, content, estimated_value)
                    SELECT r_id, package_id, reported_height, reported_width, reported_depth, reported_weight, content, estimated_value
                    FROM packages
                    WHERE request_id = request_id AND package_id = i;

                    UPDATE packages
                    SET reported_height = resubmit_request.reported_height[i],
                        reported_width = resubmit_request.reported_width[i],
                        reported_depth = resubmit_request.reported_depth[i],
                        reported_weight = resubmit_request.reported_weight[i],
                        actual_height = NULL,
                        actual_width = NULL,
                        actual_depth = NULL,
                        actual_weight = NULL
                    WHERE request_id = r_id AND package_id = i;
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
    -- Functions
        -- view_trajectory
            CREATE OR REPLACE FUNCTION view_trajectory (request_id INTEGER)
            RETURNS TABLE (source_address TEXT, destination_address TEXT, start_time TIMESTAMP, end_time TIMESTAMP)
            AS $$
            BEGIN
                RETURN QUERY 
                WITH return_legs_path AS (
                    SELECT 
                    l1_f.address as source_address,
                    COALESCE(l2_f.address, (SELECT pickup_addr FROM delivery_requests WHERE delivery_requests.id = view_trajectory.request_id)) as destination_address,
                    l1.start_time,
                    l1.end_time
                    FROM return_legs as l1
                        LEFT OUTER JOIN return_legs as l2 ON l1.request_id = l2.request_id AND l1.leg_id = l2.leg_id - 1
                        FULL OUTER JOIN facilities as l2_f ON l2_f.id = l2.source_facility
                        FULL OUTER JOIN facilities as l1_f ON l1_f.id = l1.source_facility
                    WHERE l1.request_id = view_trajectory.request_id
                ), legs_path AS (
                    SELECT
                    COALESCE(l1_f.address, (SELECT pickup_addr FROM delivery_requests WHERE delivery_requests.id = view_trajectory.request_id)) as source_address,
                    COALESCE(l2_f.address, (SELECT recipient_addr FROM delivery_requests WHERE delivery_requests.id = view_trajectory.request_id)) as destination_address,
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

        -- get_top_delivery_persons
            CREATE OR REPLACE FUNCTION get_top_delivery_persons(k INTEGER)
            RETURNS TABLE (
                employee_id INTEGER
            )
            AS $$
            BEGIN
                RETURN QUERY
                    SELECT delivery_staff.id as employee_id
                    FROM (
                        SELECT handler_id
                        FROM legs
                        UNION ALL
                        SELECT handler_id
                        FROM return_legs
                        UNION ALL
                        SELECT handler_id
                        FROM unsuccessful_pickups 
                    ) trips
                    RIGHT JOIN delivery_staff ON trips.handler_id = delivery_staff.id
                    GROUP BY delivery_staff.id
                    ORDER BY COALESCE(COUNT(trips.handler_id), 0) DESC, delivery_staff.id ASC
                    LIMIT k;
            END;
            $$ LANGUAGE plpgsql;

        -- get_top_connections
            CREATE OR REPLACE FUNCTION get_top_connections(k INTEGER) 
            RETURNS TABLE (
                source_facility_id INTEGER, 
                destination_facility_id INTEGER
            ) AS $$
            BEGIN
                RETURN QUERY
                SELECT r2.source_facility_id, r2.destination_facility_id
                FROM (
                    SELECT r.source_facility_id, r.destination_facility_id, COUNT(*) as occur
                    FROM (
                        SELECT 
                        A.destination_facility as source_facility_id, 
                        B.destination_facility as destination_facility_id
                        FROM legs A, legs B
                        WHERE A.request_id = B.request_id
                        AND A.leg_id = (B.leg_id - 1)
                        UNION ALL

                        SELECT 
                        A.source_facility as source_facility_id, 
                        B.source_facility as destination_facility_id 
                        FROM return_legs A, return_legs B
                        WHERE A.request_id = B.request_id
                        AND A.leg_id = (B.leg_id - 1)
                    ) as r
                    WHERE r.source_facility_id IS NOT NULL AND r.destination_facility_id IS NOT NULL
                    GROUP BY r.source_facility_id, r.destination_facility_id
                    ORDER BY occur DESC, r.source_facility_id ASC, r.destination_facility_id ASC
                    LIMIT k
                ) as r2;
            END;
            $$ LANGUAGE plpgsql;