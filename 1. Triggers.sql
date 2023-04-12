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
            RAISE EXCEPTION 'Package IDs for delivery request % must be consecutive integers.', NEW.request_id;
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
        IF NEW.pickup_time < (SELECT submission_time FROM delivery_requests WHERE id = NEW.request_id) THEN
            RAISE EXCEPTION 'Unsuccessful pickup timestamps for delivery request % must be after the submission time of the corresponding delivery request.', NEW.request_id;
        END IF;

        -- Check if the current pickup timestamp is after the previous pickup timestamp (if any)
        IF (last_pickup_time IS NOT NULL) AND (last_pickup_time < NEW.pickup_time) THEN
            RAISE EXCEPTION 'Unsuccessful pickup timestamps for delivery request % must be ordered.', NEW.request_id;
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
            IF (NEW.start_time < subm_time) THEN
                RAISE EXCEPTION 'Invalid start time for first leg, start_time of first leg cannot be before time the delivery request was placed';
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

-- unsuccessful deliveries //TODO
-- cancelled requests
    CREATE OR REPLACE FUNCTION check_cancelled_requests()
    RETURNS TRIGGER AS $$
    DECLARE
        sub_time INTEGER;
    BEGIN
        SELECT submission_time INTO sub_time
        FROM delivery_requests
        WHERE delivery_request.id = NEW.id
        IF (sub_time IS NOT NULL) AND (sub_time >= NEW.cancel_time) THEN
            RAISE EXCEPTION 'For cancelled request %, the cancel_time should be after the submission_time of the corresponding delivery request.', NEW.id;
        END IF;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    
    CREATE TRIGGER cancelled_requests
    BEFORE INSERT ON canselled_requests
    FOR EACH ROW
    EXECUTE FUNCTION check_cancelled_requests();
    
-- return legs 
CREATE OR REPLACE FUNCTION check_return_legs_insertion()
RETURNS TRIGGER AS $$
DECLARE 
    request_id integer;
    cancel_time timestamp;
    existing_end_time timestamp;
    existing_leg_id integer;
BEGIN
    SELECT request_id INTO request_id 
    FROM legs 
    WHERE NEW.request_id = legs.request_id

    -- constraint 8 
    IF NOT EXISTS request_id THEN 
        RETURN NULL;
    END IF;
    
    -- the return_leg’s start_time should be after the cancel_time of the request (if any).
    SELECT cancel_time INTO cancel_time FROM cancelled_requests 
    WHERE NEW.request_id = cancelled_requests.id;
    IF cancel_time IS NOT NULL AND NEW.start_time < cancel_time THEN
        RAISE EXCEPTION 'Start time cannot be earlier than cancel time';
    END IF;
    -- first leg condition
    IF NOT EXISTS SELECT 1 from return_legs WHERE NEW.request_id = return_legs.request_id
        NEW.leg_id = 1 
        RETURN NEW;
    END IF;
    
    -- from here on, we confirm have an existing leg, trace the existing end time and leg id
    SELECT leg_id, end_time INTO existing_leg_id, existing_end_time 
    FROM return_legs 
    WHERE leg_id = 
        (SELECT MAX(leg_id) FROM return_legs WHERE NEW.request_id = return_legs.request_id);
    -- constrain 9
    IF leg_id = 3 THEN
        RAISE EXCEPTION 'there can be at most three unsuccessful_return_deliveries.';
    END IF;
    IF NEW.start_time < existing_end_time THEN
        RAISE EXCEPTION 'Start time cannot be earlier than previous end_time';
    END IF;
    NEW.leg_id = existing_leg_id + 1
    RETURN NEW


-- unsuccessful return deliveries
    CREATE OR REPLACE FUNCTION check_unsuccessful_return_deliveries()
    RETURNS TRIGGER AS $$
    DECLARE
        s_time INTEGER;
    BEGIN
        SELECT start_time INTO s_time
        FROM return_legs
        WHERE return_legs.request_id = NEW.request_id
        IF (s_time IS NOT NULL) AND (s_time >= NEW.attempt_time) THEN
            RAISE EXCEPTION 'For unsuccessful_return_deliveries %, the attempt_time should be after the start_time of corresponding return_leg.', NEW.request_id;
        END IF;
        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER unsuccessful_return_deliveries
    BEFORE INSERT ON unsuccessful_return_deliveries
    FOR EACH ROW
    EXECUTE FUNCTION check_unsuccessful_return_deliveries();

