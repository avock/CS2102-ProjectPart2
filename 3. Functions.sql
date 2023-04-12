-- view_trajectory
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
        
        SELECT 
            pickup_addr AS source_addr,
            recipient_addr AS destination_addr,
            submission_time AS start_time,
            (SELECT MIN(start_time) FROM legs WHERE request_id = delivery_requests.id) AS end_time
        FROM delivery_requests
        WHERE id = request_id
        
        UNION
        
        SELECT 
            legs.source_addr,
            legs.destination_addr,
            legs.start_time,
            legs.end_time
        FROM legs
        WHERE request_id = request_id
        
        UNION
        
        SELECT 
            return_legs.source_addr,
            return_legs.destination_addr,
            return_legs.start_time,
            return_legs.end_time
        FROM return_legs
        WHERE request_id = request_id
        
        ORDER BY start_time ASC;
    END;
    $$ LANGUAGE plpgsql;
-- get_top_delivery_persons //TODO
-- get_top_connections //TODO