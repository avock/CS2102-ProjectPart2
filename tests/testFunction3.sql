DROP TABLE IF EXISTS unsuccessful_return_deliveries;
DROP TABLE IF EXISTS return_legs;
DROP TABLE IF EXISTS unsuccessful_deliveries;
DROP TABLE IF EXISTS legs;
DROP TABLE IF EXISTS unsuccessful_pickups;
DROP TABLE IF EXISTS cancelled_requests;
DROP TABLE IF EXISTS cancelled_or_unsuccessful_requests;
DROP TABLE IF EXISTS accepted_requests;
DROP TABLE IF EXISTS packages;
DROP TABLE IF EXISTS delivery_requests;
DROP TABLE IF EXISTS delivery_staff;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS facilities;

CREATE TABLE customers (
	id SERIAL PRIMARY KEY,
	name TEXT NOT NULL,
	gender gender_type NOT NULL,
	mobile TEXT NOT NULL
);

CREATE TABLE employees (
	id SERIAL PRIMARY KEY,
	name TEXT NOT NULL,
	gender gender_type NOT NULL,
	dob DATE NOT NULL,
	title TEXT NOT NULL,
	salary NUMERIC NOT NULL,
	CHECK (salary >= 0)
);

CREATE TABLE delivery_staff (
	id INTEGER PRIMARY KEY NOT NULL REFERENCES employees(id) 
);

CREATE TABLE delivery_requests (
	id SERIAL PRIMARY KEY,
	customer_id INTEGER NOT NULL REFERENCES customers(id),
	evaluater_id INTEGER NOT NULL REFERENCES employees(id),
	status delivery_status NOT NULL,
	pickup_addr TEXT NOT NULL,
	pickup_postal TEXT NOT NULL,
	recipient_name TEXT NOT NULL,
	recipient_addr TEXT NOT NULL,
	recipient_postal TEXT NOT NULL,
	submission_time TIMESTAMP NOT NULL,
	pickup_date DATE,
	num_days_needed INTEGER,
	price NUMERIC
);

CREATE TABLE packages (
	request_id INTEGER REFERENCES delivery_requests(id),
	package_id INTEGER,
	reported_height NUMERIC NOT NULL,
	reported_width NUMERIC NOT NULL,
	reported_depth NUMERIC NOT NULL,
	reported_weight NUMERIC NOT NULL,
	content TEXT NOT NULL,
	estimated_value NUMERIC NOT NULL,
	actual_height NUMERIC,
	actual_width NUMERIC,
	actual_depth NUMERIC,
	actual_weight NUMERIC,
	PRIMARY KEY (request_id, package_id)
);

CREATE TABLE accepted_requests (
	id INTEGER PRIMARY KEY REFERENCES delivery_requests(id),
	card_number TEXT NOT NULL,
	payment_time TIMESTAMP NOT NULL,
	monitor_id INTEGER NOT NULL REFERENCES employees(id)
);

CREATE TABLE cancelled_or_unsuccessful_requests (
	id INTEGER PRIMARY KEY REFERENCES accepted_requests(id)
);

CREATE TABLE cancelled_requests (
	id INTEGER PRIMARY KEY REFERENCES accepted_requests(id),
	cancel_time TIMESTAMP NOT NULL
);

CREATE TABLE unsuccessful_pickups (
	request_id INTEGER REFERENCES accepted_requests(id),
	pickup_id INTEGER,
	handler_id INTEGER NOT NULL REFERENCES delivery_staff(id),
	pickup_time TIMESTAMP NOT NULL,
	reason TEXT,
	PRIMARY KEY (request_id, pickup_id)
);

CREATE TABLE facilities (
	id SERIAL PRIMARY KEY,
	address TEXT NOT NULL,
	postal TEXT NOT NULL
);
	
CREATE TABLE legs (
	request_id INTEGER REFERENCES accepted_requests(id),
	leg_id INTEGER,
	handler_id INTEGER NOT NULL REFERENCES delivery_staff(id),	
    start_time TIMESTAMP NOT NULL,
	end_time TIMESTAMP,
	destination_facility INTEGER REFERENCES facilities(id),
	PRIMARY KEY (request_id, leg_id)
);

CREATE TABLE unsuccessful_deliveries (
    request_id INTEGER,
    leg_id INTEGER,
    reason TEXT NOT NULL,
    attempt_time TIMESTAMP NOT NULL,
	PRIMARY KEY (request_id, leg_id),
    FOREIGN KEY (request_id, leg_id) REFERENCES legs(request_id, leg_id)
);

CREATE TABLE return_legs (
	request_id INTEGER REFERENCES cancelled_or_unsuccessful_requests(id),
	leg_id INTEGER,
	handler_id INTEGER NOT NULL REFERENCES delivery_staff(id),	
    start_time TIMESTAMP NOT NULL,
    source_facility INTEGER NOT NULL REFERENCES facilities(id),
	end_time TIMESTAMP,
	PRIMARY KEY (request_id, leg_id)
);

CREATE TABLE unsuccessful_return_deliveries (
    request_id INTEGER,
    leg_id INTEGER,
    reason TEXT NOT NULL,
    attempt_time TIMESTAMP NOT NULL,
	PRIMARY KEY (request_id, leg_id), 
    FOREIGN KEY (request_id, leg_id) REFERENCES return_legs(request_id, leg_id)
);

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
-- get_top_connection function
DROP FUNCTION IF EXISTS get_top_connections(k INTEGER);
CREATE OR REPLACE FUNCTION get_top_connections(k INTEGER) 
RETURNS TABLE (
	source_facility_id INTEGER, 
	destination_facility_id INTEGER
) AS $$
BEGIN
	-- leg 1 -> leg 2 -> leg 3
	-- faci1 -> faci2 -> faci3 
	-- faci1 . faci2
	-- faci2 . faci3
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
			-- Might not be needed 
			--AND A.end_time = B.start_time

			UNION ALL

			SELECT 
			A.source_facility as source_facility_id, 
			B.source_facility as destination_facility_id 
			FROM return_legs A, return_legs B
			WHERE A.request_id = B.request_id
			AND A.leg_id = (B.leg_id - 1)
			-- Might not be needed 
			--AND A.end_time = B.start_time
		) as r
		WHERE r.source_facility_id IS NOT NULL AND r.destination_facility_id IS NOT NULL
		GROUP BY r.source_facility_id, r.destination_facility_id
		ORDER BY occur DESC, r.source_facility_id ASC, r.destination_facility_id ASC
		LIMIT k
	) as r2;
END;
$$ LANGUAGE plpgsql;

-- get_top_connection function
DROP FUNCTION IF EXISTS get_top_connections2(k INTEGER);
CREATE OR REPLACE FUNCTION get_top_connections2(k INTEGER) 
RETURNS TABLE (
	source_facility_id INTEGER, 
	destination_facility_id INTEGER,
	occurence INTEGER
) AS $$
BEGIN

	RETURN QUERY
		SELECT r.source_facility_id, r.destination_facility_id, CAST(COUNT(*) AS INTEGER) as occur
		FROM (
			SELECT 
			A.destination_facility as source_facility_id, 
			B.destination_facility as destination_facility_id
			FROM legs A, legs B
			WHERE A.request_id = B.request_id
			AND A.leg_id = (B.leg_id - 1)
			-- Might not be needed 
			--AND A.end_time = B.start_time

			UNION ALL

			SELECT 
			A.source_facility as source_facility_id, 
			B.source_facility as destination_facility_id 
			FROM return_legs A, return_legs B
			WHERE A.request_id = B.request_id
			AND A.leg_id = (B.leg_id - 1)
			-- Might not be needed 
			--AND A.end_time = B.start_time
		) as r
		WHERE r.source_facility_id IS NOT NULL AND r.destination_facility_id IS NOT NULL
		GROUP BY r.source_facility_id, r.destination_facility_id
		ORDER BY occur DESC, r.source_facility_id ASC, r.destination_facility_id ASC
		LIMIT k;
END;
$$ LANGUAGE plpgsql;

alter sequence customers_id_seq restart with 1;
alter sequence delivery_requests_id_seq restart with 1;
alter sequence employees_id_seq restart with 1;
alter sequence facilities_id_seq restart with 1;

INSERT INTO customers(name, gender, mobile)
VALUES ('Jane Doe', 'female', '555-5555');

INSERT INTO employees(name, gender, dob, title, salary)
VALUES ('John Doe', 'male', '1990-01-01', 'Delivery Staff', 40000);
INSERT INTO delivery_requests 
VALUES (
	1,
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
    1,
    1,
    10,
    20,
    30,
    50,
    'Clothes',
    200
    );
INSERT INTO facilities (id, address, postal)
VALUES
  (1, '123 Main St.', '12345'),
  (2, '456 Elm St.', '67890'),
  (3, '789 Oak St.', '13579'),
  (4, '246 Maple St.', '46801'),
  (5, '135 Pine St.', '79135'),
  (6, '579 Cedar St.', '02468'),
  (7, '802 Walnut St.', '35791'),
  (8, '246 Cherry St.', '68013'),
  (9, '135 Oak St.', '97531'),
  (10, '579 Cedar St.', '02468');

INSERT INTO delivery_staff 
VALUES (1);

INSERT INTO accepted_requests (id, card_number, payment_time, monitor_id)
VALUES (1, '1234-5678-9012-3456', '2023-04-12 16:00:00', 1);

--Initialization
INSERT INTO cancelled_or_unsuccessful_requests
VALUES (1);

-- INSERT INTO cancelled_requests (id, cancel_time)
--     VALUES (1, 
--     -- would fail here, as the timestamp is ≤ the subm_time		
--     --'2023-04-12 15:30:00');
-- 	'2023-04-12 16:40:00');


INSERT INTO legs (request_id,leg_id,handler_id,start_time,end_time,destination_facility) 
VALUES 
(1, 1, 1, '2023-04-12 16:00:00', '2023-04-12 16:00:00', 1) ,
(1, 2, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 3, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 4, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 5, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 6, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 7, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 8, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 9, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 10, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 11, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 12, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 13, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 14, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 15, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 16, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 17, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 18, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 19, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 20, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 21, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 9) ,
(1, 22, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 9) ,
(1, 23, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 24, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 25, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 26, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 27, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 28, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 29, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 30, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 31, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 32, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 33, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 34, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 35, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 36, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 37, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 38, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 39, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 40, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 41, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 42, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 43, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 44, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 45, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 46, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 47, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 48, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 49, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 50, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 51, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 52, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 53, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 54, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 7) ,
(1, 55, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 56, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 57, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 58, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 59, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 7) ,
(1, 60, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 61, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 62, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 63, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 64, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 65, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 66, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 67, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 68, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 69, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 70, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 71, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 72, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 73, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 74, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 75, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 76, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 77, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 78, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 7) ,
(1, 79, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 80, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 81, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 82, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 4) ,
(1, 83, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 84, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 85, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 86, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 87, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 88, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 89, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 90, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 91, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 92, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 93, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 94, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 95, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 96, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 97, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 98, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 99, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 100, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 101, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 102, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 103, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 104, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 105, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 106, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 107, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 108, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 109, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 110, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 111, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 112, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 113, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 114, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 115, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 116, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 117, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 118, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 119, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 120, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 121, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 122, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 123, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 124, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 7) ,
(1, 125, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 126, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 127, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 9) ,
(1, 128, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 129, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 130, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 131, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 132, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 133, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 4) ,
(1, 134, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 135, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 136, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 9) ,
(1, 137, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 138, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 139, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 140, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 141, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 142, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 143, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 144, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 145, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 146, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 147, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 148, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 149, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 150, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 151, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 152, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 153, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 154, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 155, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 156, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 157, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 158, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 159, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 160, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 161, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 162, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 163, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 164, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 165, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 166, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 167, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 168, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 169, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 170, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 171, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 172, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 173, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 174, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 175, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 176, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 177, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 178, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 179, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 180, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 181, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 182, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 183, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 184, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 185, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 186, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 187, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 188, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 189, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 190, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 191, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 192, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 193, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 194, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 195, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 196, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 197, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 198, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 199, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 200, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 201, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 202, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 203, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 4) ,
(1, 204, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 205, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 206, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 207, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 208, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 209, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 210, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 211, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 212, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 213, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 214, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 9) ,
(1, 215, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 4) ,
(1, 216, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 217, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 218, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 219, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 220, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 4) ,
(1, 221, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 6) ,
(1, 222, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 223, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 224, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 225, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 8) ,
(1, 226, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 227, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 228, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 5) ,
(1, 229, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 230, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 231, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 4) ,
(1, 232, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 9) ,
(1, 233, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 234, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 235, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 236, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 237, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 238, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 239, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 240, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 241, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 242, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 243, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 244, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 245, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
-- (1, 245, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', NULL) ,
(1, 246, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 247, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 248, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 249, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 250, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 251, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 252, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 253, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 254, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 4) ,
(1, 255, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 256, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 257, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 258, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 5) ,
(1, 259, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 1) ,
(1, 260, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 8) ,
(1, 261, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 262, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 7) ,
(1, 263, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 264, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 265, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 266, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 267, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 10) ,
(1, 268, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 269, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 270, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 271, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 272, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 9) ,
(1, 273, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 274, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 275, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 2) ,
(1, 276, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 277, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 4) ,
(1, 278, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 279, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 8) ,
(1, 280, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 281, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 2) ,
(1, 282, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 2) ,
(1, 283, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 284, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 9) ,
(1, 285, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 286, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 9) ,
(1, 287, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 10) ,
(1, 288, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ,
(1, 289, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 6) ,
(1, 290, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 291, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 3) ,
(1, 292, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 7) ,
(1, 293, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 3) ,
(1, 294, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 3) ,
(1, 295, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 4) ,
(1, 296, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 1) ,
(1, 297, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 6) ,
(1, 298, 1, '2023-04-12 16:00:01', '2023-04-12 16:00:00', 1) ,
(1, 299, 1, '2023-04-12 16:00:02', '2023-04-12 16:00:00', 10) ,
(1, 300, 1, '2023-04-12 16:00:03', '2023-04-12 16:00:00', 5) ;
-- ('8 to 1', 9)
-- ('10 to 1', 7)
-- ('1 to 3', 7)
-- ('5 to 8', 7)
-- ('9 to 6', 6)
-- ('2 to 8', 6)
-- ('1 to 2', 5)
-- ('2 to 9', 5)
-- ('9 to 4', 5)
-- ('1 to 10', 5)

INSERT INTO return_legs (request_id,leg_id,handler_id,start_time,end_time,source_facility) 
VALUES 
(1, 1, 1, '2023-04-12 16:01:00', '2023-04-12 16:00:00', 8),
(1, 2, 1, '2023-04-12 16:01:00', '2023-04-12 16:00:00', 1),
(1, 3, 1, '2023-04-12 16:01:00', '2023-04-12 16:00:00', 2),
(1, 4, 1, '2023-04-12 16:01:00', '2023-04-12 16:00:00', 1),
(1, 5, 1, '2023-04-12 16:01:00', '2023-04-12 16:00:00', 2);
SELECT * FROM get_top_connections(10);
SELECT * FROM get_top_connections2(10);
