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

        -- Constraint 5: Check if the unsuccessful delivery timestamp is after the start time
        IF NEW.attempt_time < curr_start_time THEN
            RAISE EXCEPTION 'The timestamp of unsuccessful_delivery for delivery_requst % should be after the start_time of the corresponding leg.', NEW.request_id;
        END IF;

        -- Count the number of unsuccessful deliveries for the request
        SELECT COUNT(*) INTO unsuccessful_count
        FROM unsuccessful_deliveries
        WHERE request_id = NEW.request_id;

        -- Constraint 6: Check if there are more than three unsuccessful deliveries for the request
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
    -- trigger 7
        CREATE OR REPLACE FUNCTION return_leg_id()
        RETURNS TRIGGER AS $$
        DECLARE 
            max_return_leg_id INTEGER;
        BEGIN
            SELECT MAX(leg_id) INTO max_return_leg_id
            FROM return_legs
            WHERE return_legs.request_id = NEW.request_id;

            IF max_return_leg_id IS NULL THEN
                IF NEW.leg_id <> 1 THEN
                    RAISE EXCEPTION 'First leg ID must be 1';
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

        CREATE TRIGGER check_return_leg_id
        BEFORE INSERT ON return_legs
        FOR EACH ROW
        EXECUTE FUNCTION return_leg_id();

    -- trigger 8
        CREATE OR REPLACE FUNCTION consistency_return_legs_insertion()
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

            -- -- If there is no existing leg, then the start time must be after the end time of the last leg
            -- SELECT leg_id, end_time INTO existing_leg_id, last_existing_leg_end_time 
            -- FROM return_legs 
            -- WHERE leg_id = 
            --     (SELECT MAX(leg_id) FROM return_legs WHERE NEW.request_id = return_legs.request_id)
            -- AND NEW.request_id = return_legs.request_id;

            -- IF existing_leg_id IS NOT NULL THEN
            --     IF NEW.start_time < last_existing_leg_end_time THEN
            --         RAISE EXCEPTION 'Start time must be after the end time of the last return leg';
            --     END IF;
            -- END IF;
			
			-- IMPORTANT
			-- CK's understanding
			-- start time of RETURN LEG must be afer end time of the LATEST LEG (not return leg)
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

        CREATE TRIGGER check_consistency_return_legs_insertion
        BEFORE INSERT ON return_legs
        FOR EACH ROW
        EXECUTE FUNCTION consistency_return_legs_insertion();
    -- trigger 9
        CREATE OR REPLACE FUNCTION at_most_three_unsuccessful_return_deliveries()
        RETURNS TRIGGER AS $$
        DECLARE 
            unsuccessful_count INTEGER;
        BEGIN
        -- Count the number of unsuccessful deliveries for the request
            SELECT COUNT(*) INTO unsuccessful_count
            FROM unsuccessful_return_deliveries
            WHERE unsuccessful_return_deliveries.request_id = NEW.request_id;

            -- Constraint 6: Check if there are more than three unsuccessful deliveries for the request
            IF unsuccessful_count >= 3 THEN
                RAISE EXCEPTION 'For delivery request ID=%, there can be at most 3 unsuccessful_return_deliveries.', NEW.request_id;
            END IF;
            RETURN NEW;

        END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER check_at_most_three_unsuccessful_return_deliveries
        BEFORE INSERT ON return_legs
        FOR EACH ROW
        EXECUTE FUNCTION at_most_three_unsuccessful_return_deliveries();

-- unsuccessful return deliveries
    CREATE OR REPLACE FUNCTION check_unsuccessful_return_deliveries()
    RETURNS TRIGGER AS $$
    DECLARE
        s_time TIMESPAMP;
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

