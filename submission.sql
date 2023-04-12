-- leg q2 --
CREATE OR REPLACE FUNCTION check_first_leg_start_time1()
RETURNS TRIGGER AS $$
DECLARE
  submission_time TIMESTAMP;
BEGIN
  SELECT submission_time INTO submission_time FROM delivery_requests WHERE id = NEW.request_id;
    WHERE (request_id = NEW.request_id) AND (leg_id = 1);
  IF (NEW.leg_id = 1) THEN
    IF (NEW.start_time < submission_time) THEN 
        RAISE EXCEPTION 'Invalid start time for first leg, start_time of first leg cnanot be before time the delivery request was placed';
    END IF;
  END IF;
  RETURN NEW;
END;

--leg q3--
CREATE OR REPLACE FUNCTION check_first_leg_start_time2()
RETURNS TRIGGER AS $$
DECLARE
  last_unsuccessful_pickup_time TIMESTAMP;
BEGIN
  SELECT MAX(attempt_time) INTO last_unsuccessful_pickup_time FROM unsuccessful_pickups WHERE request_id = NEW.request_id;
  IF (NEW.leg_id = 1) THEN
    IF (last_unsuccessful_pickup_time IS NOT NULL) AND (NEW.start_time < last_unsuccessful_pickup_time) THEN
        RAISE EXCEPTION 'Invalid start time for first leg, start_time of first leg cannot be before last unsuccesful pickup time';
    END IF;
  END IF; 
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- leg q4 --
CREATE OR REPLACE FUNCTION check_leg_start_and_end_time()
RETURNS TRIGGER AS $$
DECLARE
  last_leg_end_time TIMESTAMP;
BEGIN
  SELECT end_time INTO last_leg_end_time FROM legs WHERE request_id = NEW.request_id AND leg_id = NEW.leg_id - 1;
  IF NEW.leg_id > 1 AND last_leg_end_time IS NULL THEN
    RAISE EXCEPTION 'Invalid start time for leg, end time of previous leg is NULL'
  END IF;
  IF NEW.leg_id > 1 AND NEW.start_time <= last_leg_end_time THEN
    RAISE EXCEPTION 'Invalid start time for leg, must not be before end time of previous leg';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- routine --
CREATE OR REPLACE PROCEDURE submit_request(
  customer_id INTEGER,
  evaluator_id INTEGER,
  pickup_addr TEXT,
  pickup_postal TEXT,
  recipient_name TEXT,
  recipient_addr TEXT,
  recipient_postal TEXT,
  submission_time TIMESTAMP,
  package_num INTEGER,
  reported_height INTEGER[],
  reported_width INTEGER[],
  reported_depth INTEGER[],
  reported_weight INTEGER[],
  content TEXT[],
  estimated_value NUMERIC[]
)
AS $$
DECLARE
  request_id INTEGER;
  package_id INTEGER;
BEGIN

  -- Insert delivery request
  INSERT INTO delivery_requests (
    customer_id,
    evaluater_id,
    status,
    pickup_addr,
    pickup_postal,
    recipient_name,
    recipient_addr,
    recipient_postal,
    submission_time
  )
  VALUES (
    customer_id,
    evaluator_id,
    'submitted',
    pickup_addr,
    pickup_postal,
    recipient_name,
    recipient_addr,
    recipient_postal,
    submission_time
  )
  RETURNING id INTO request_id;

  -- Insert packages for the delivery request
  FOR i IN 1..package_num LOOP
    INSERT INTO packages (
      request_id,
      package_id,
      reported_height,
      reported_width,
      reported_depth,
      reported_weight,
      content,
      estimated_value
    )
    VALUES (
      request_id,
      i,
      reported_height[i],
      reported_width[i],
      reported_depth[i],
      reported_weight[i],
      content[i],
      estimated_value[i]
    );
  END LOOP;

  -- Set actual dimensions to NULL for each package
  UPDATE packages
  SET actual_height = NULL,
      actual_width = NULL,
      actual_depth = NULL,
      actual_weight = NULL
  WHERE request_id = request_id;

  -- Set pickup_date, num_days_needed, and price to NULL for the delivery request
  UPDATE delivery_requests
  SET pickup_date = NULL,
      num_days_needed = NULL,
      price = NULL
  WHERE id = request_id;
END;

$$ LANGUAGE plpgsql;

--function--
    CREATE OR REPLACE FUNCTION view_trajectory(request_id INTEGER)
    RETURNS TABLE (
        source_addr TEXT,
        destination_addr TEXT,
        start_time TIMESTAMP,
        end_time TIMESTAMP
    )
    AS $$
    BEGIN
        RETURN QUERY
        SELECT pickup_addr AS source_addr,
            recipient_addr AS destination_addr,
            submission_time AS start_time,
            (SELECT MIN(start_time) FROM legs WHERE request_id = delivery_requests.id) AS end_time
        FROM delivery_requests
        WHERE id = request_id
        
        UNION
        
        SELECT legs.source_addr,
            legs.destination_addr,
            legs.start_time,
            legs.end_time
        FROM legs
        WHERE request_id = request_id
        
        UNION
        
        SELECT return_legs.source_addr,
            return_legs.destination_addr,
            return_legs.start_time,
            return_legs.end_time
        FROM return_legs
        WHERE request_id = request_id
        
        ORDER BY start_time ASC;
    END;
    $$ LANGUAGE plpgsql;