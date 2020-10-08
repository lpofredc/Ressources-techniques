﻿CREATE OR REPLACE FUNCTION MY_TO_DATE( p_date_str CHARACTER VARYING, p_format_mask CHARACTER VARYING ) RETURNS DATE
IMMUTABLE
LANGUAGE plpgsql AS
$$
  DECLARE l_date DATE;
  DECLARE i_date_str CHARACTER VARYING;

BEGIN

SELECT INTO i_date_str UNACCENT(LOWER(p_date_str));
SELECT INTO i_date_str REPLACE(i_date_str, 'janvier', 'january');
SELECT INTO i_date_str REPLACE(i_date_str, 'fevrier', 'february');
SELECT INTO i_date_str REPLACE(i_date_str, 'mars', 'march');
SELECT INTO i_date_str REPLACE(i_date_str, 'avril', 'april');
SELECT INTO i_date_str REPLACE(i_date_str, 'mai', 'may');
SELECT INTO i_date_str REPLACE(i_date_str, 'juin', 'june');
SELECT INTO i_date_str REPLACE(i_date_str, 'juillet', 'july');
SELECT INTO i_date_str REPLACE(i_date_str, 'aout', 'august');
SELECT INTO i_date_str REPLACE(i_date_str, 'septembre', 'september');
SELECT INTO i_date_str REPLACE(i_date_str, 'novembre', 'november');
SELECT INTO i_date_str REPLACE(i_date_str, 'decembre', 'december');


  SELECT INTO l_date to_date( i_date_str, p_format_mask );
  RETURN l_date;
EXCEPTION
  WHEN others THEN
    RETURN null;
END;
$$;


DROP TABLE IF EXISTS export_oo.t_releves_occtax CASCADE;
CREATE TABLE export_oo.t_releves_occtax AS 
WITH date_precomp AS (
SELECT 
	id_obs,
	date_obs,
	date_textuelle,

	CASE 
		WHEN date_debut_obs IS NOT NULL 
			THEN date_debut_obs
		WHEN date_textuelle LIKE '%été%'
			THEN (MY_TO_DATE(SUBSTRING(date_textuelle, '\d{4}'), 'YYYY') + interval '6 month')::DATE
		WHEN date_textuelle LIKE '%juillet aout%' 
			THEN (MY_TO_DATE(SUBSTRING(date_textuelle, '\d{4}'), 'YYYY') + interval '6 month')::DATE
		WHEN date_textuelle LIKE '%avril-mai%' 
			THEN (MY_TO_DATE(SUBSTRING(date_textuelle, '\d{4}'), 'YYYY') + interval '3 month')::DATE
		ELSE NULL
	END AS date_min,

	CASE 
		WHEN date_fin_obs IS NOT NULL 
			THEN date_fin_obs
		WHEN date_textuelle LIKE '%été%'
			THEN (MY_TO_DATE(SUBSTRING(date_textuelle, '\d{4}'), 'YYYY') + interval '8 month' - interval '1 day')::DATE
		WHEN date_textuelle LIKE '%juillet%aout%'
			THEN (MY_TO_DATE(SUBSTRING(date_textuelle, '\d{4}'), 'YYYY') + interval '8 month' - interval '1 day')::DATE
		WHEN date_textuelle LIKE '%avril-mai%' 
			THEN (MY_TO_DATE(SUBSTRING(date_textuelle, '\d{4}'), 'YYYY') + interval '8 month' - interval '1 day')::DATE

		ELSE NULL
	END AS date_max,

	CASE
		WHEN heure_obs IS NOT NULL
			THEN heure_obs
		WHEN date_textuelle LIKE '%de%à%'
			THEN TO_TIMESTAMP(SUBSTRING(REPLACE(date_textuelle, 'minuit', '0 h 00'), '(\d?\d h \d{2})'), 'HH24 h MI')::TIME
		ELSE NULL
	END AS hour_min,

	CASE 
		WHEN date_textuelle LIKE '%de%à%'
			THEN TO_TIMESTAMP(SUBSTRING(REPLACE(date_textuelle, 'minuit', '0 h 00'), '(\d?\d h \d{2})$'), 'HH24 h MI')::TIME
		ELSE NULL
	END AS hour_max,


	COALESCE(
		MY_TO_DATE(date_textuelle, 'YYYY'),
		MY_TO_DATE(LOWER(date_textuelle), 'TMmonth YYYY')
	) AS date_from_text
	
	FROM saisie.saisie_observation 

), date_comp AS (
	SELECT 
		id_obs,
		COALESCE(date_min, date_obs, date_from_text) AS date_min,
		CASE 
			WHEN	hour_min IS NOT NULL 
				AND hour_max IS NOT NULL 
				AND hour_max < hour_min
				AND date_max IS NULL
				THEN (COALESCE(date_min, date_obs, date_from_text) + interval '1 day')::DATE
			ELSE COALESCE(date_max, date_min, date_obs, date_from_text)
		END AS date_max,
		hour_min,
		hour_max,
		date_from_text,
		date_textuelle,
		date_obs

	FROM date_precomp

), observers AS (
	SELECT 
		id_obs,
		REGEXP_SPLIT_TO_ARRAY(observateur, '&') AS observers
		FROM saisie.saisie_observation
), elevation AS (
	SELECT
		id_obs,
		CASE WHEN elevation::int >= 0 THEN elevation::int ELSE NULL END AS alt_min,
		CASE WHEN elevation::int < 0 THEN elevation::int ELSE NULL END AS depth_min
		FROM saisie.saisie_observation
)		

SELECT 
	COUNT(*),
	d.date_min,
	d.date_max,
	d.hour_min,
	d.hour_max,
	o.geometrie,
	e.alt_min AS altitude_min,
	e.depth_min,
	id_protocole,
	id_etude,
	ARRAY_AGG(o.id_obs) AS ids_obs,
	ob.observers,
	numerisateur,
	'133' AS cd_nomenclature_tech_collect_campanule, -- (Non renseigné) 'TECHNIQUE_OBS'
	'NSP' AS cd_nomenclature_grp_typ, -- TYP_GRP
	
	-- place_name id_lieu_dit
	-- date_minmax
	-- hour minmax
	STRING_AGG(DISTINCT o.remarque_obs, ', ') AS comment, --comment
	export_oo.get_synonyme_cd_nomenclature('PRECISION', precision::text) AS precision,
	uuid_generate_v4() AS unique_id_sinp_grp,
	'end'
	
	FROM saisie.saisie_observation o
	
	JOIN date_comp d
		ON d.id_obs = o.id_obs
	JOIN observers ob
		ON ob.id_obs = o.id_obs
	JOIN elevation e
		ON e.id_obs = o.id_obs

GROUP BY 
	id_protocole,
	id_etude,
	altitude_min,
	depth_min,
	date_min,
	date_max,
	hour_min,
	hour_max,
	elevation,
	o.geometrie,
	ob.observers,
	numerisateur,
	precision
	
ORDER BY COUNT(*) DESC

;


