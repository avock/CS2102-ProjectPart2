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