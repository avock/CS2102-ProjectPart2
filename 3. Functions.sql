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

-- get_top_delivery_persons
    CREATE OR REPLACE FUNCTION get_top_delivery_person(k INTEGER)
    RETURNS TABLE (
        employee_id INTEGER
    )
    AS $$
    BEGIN
        RETURN QUERY
            SELECT employee_id
            FROM (
                SELECT employee_id, COUNT(*) as trip_count
                FROM (
                    SELECT legs.handler_id as employee_id
                    FROM legs
                    UNION ALL
                    SELECT return_legs.handler_id as employee_id
                    FROM return_legs
                    UNION ALL
                    SELECT unsuccessful_pickups.handler_id as employee_id
                    FROM unsuccessful_pickups 
                ) trips
                GROUP BY employee_id
                ORDER BY trip_count DESC, employee_id ASC
                LIMIT k
            ) top_delivery_persons;
    END;
    $$ LANGUAGE plpgsql;

-- get_top_connections 
    -- version1
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
                GROUP BY r.source_facility_id, r.destination_facility_id
                ORDER BY occur DESC, r.source_facility_id ASC, r.destination_facility_id ASC
                LIMIT k;
            ) as r2 
        END;
        $$ LANGUAGE plpgsql;

    -- version2
        CREATE OR REPLACE FUNCTION get_top_connections(k INTEGER) 
        RETURNS TABLE 
        (
            source_facility_id INTEGER, 
            destination_facility_id INTEGER
        ) AS $$
        BEGIN
            -- leg 1 -> leg 2 -> leg 3
            -- faci1 -> faci2 -> faci3 
            -- faci1 . faci2
            -- faci2 . faci3
            RETURN QUERY
            
            SELECT r.source_facility_id, r.destination_facility_id
            FROM
            (
                SELECT 
                A.destination_facility as source_facility_id, 
                B.destination_facility as destination_facility_id
                FROM legs A, legs B
                WHERE A.request_id = B.request_id
                AND A.leg_id = (B.leg_id - 1)
                AND A.destination_facility <> NULL
                AND B.destination_facility <> NULL
                
                UNION ALL

                SELECT 
                A.source_facility as source_facility_id, 
                B.source_facility as destination_facility_id 
                FROM return_legs A, return_legs B
                WHERE A.request_id = B.request_id
                AND A.leg_id = (B.leg_id - 1)
                AND A.source_facility <> NULL
                AND B.source_facility <> NULL
            ) as r
            GROUP BY r.source_facility_id, r.destination_facility_id
            ORDER BY COUNT(*) DESC, r.source_facility_id ASC, r.destination_facility_id ASC 
            LIMIT k;
        END;
        $$ LANGUAGE plpgsql;

    -- version3
    CREATE OR REPLACE FUNCTION get_top_connections(k INTEGER) 
    RETURNS TABLE (source_facility_id INTEGER, destination_facility_id INTEGER) AS $$
    BEGIN
        RETURN QUERY
            SELECT source_facility, destination_facility
            FROM (
                SELECT source_facility, destination_facility, COUNT(*) AS occurrences
                FROM (
                    SELECT source_facility, destination_facility
                    FROM legs
                    WHERE source_facility IS NOT NULL AND destination_facility IS NOT NULL
                    UNION ALL
                    SELECT source_facility, destination_facility
                    FROM return_legs
                    WHERE source_facility IS NOT NULL AND destination_facility IS NOT NULL
                ) AS connections
                GROUP BY source_facility, destination_facility
            ) AS connection_counts
            ORDER BY occurrences DESC, source_facility, destination_facility
            LIMIT k;
    END;
    $$ LANGUAGE plpgsql;
