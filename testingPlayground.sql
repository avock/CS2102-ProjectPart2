-- FUNCTION: public.check_delivery_request_packages()

-- DROP FUNCTION IF EXISTS public.check_delivery_request_packages();

CREATE OR REPLACE FUNCTION public.check_delivery_request_packages()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    last_package_id INTEGER;
BEGIN
    SELECT MAX(package_id) INTO last_package_id
    FROM packages 
    WHERE request_id = NEW.request_id;
    
    IF (last_package_id IS NOT NULL) AND (last_package_id != NEW.package_id - 1) THEN
        RAISE EXCEPTION 'Package IDs for delivery request % must be consecutive integers starting from 1.', NEW.package_id;
    END IF;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION public.check_delivery_request_packages()
    OWNER TO postgres;
