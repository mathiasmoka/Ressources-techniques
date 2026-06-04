-----------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------					Complétude des inventaires -> courbes d'accumulation 						-------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- L'inventaire sur mon secteur d'intérêt atteint-il un niveau de complétude satisfaisant? 
-- Pour le savoir, le mieux est de réaliser une courbe d'accumulation avec 
--			- X = nombre de jours d'inventaire (voire accumulation de l'effort homme/jour!) et 
--			- Y = le nombre d'espèces cumulées.
-- Ce script permet de sortir ces données pour les reporter directement dans un graphique:
-- 			- regne
-- 			- group1_inpn (ou group2_inpn)  (seuls les taxons précis à l'espèce ou à des rangs plus précis - sous-espèce, etc - sont pris en compte)
-- 			- nombre_jours_cumules
-- 			- effort_homme_jour_cumule (là, on a splité le champ "observers")
-- 			- nombre_especes_cumulees
-- 			- numero_jour + jour
-- Bien sûr, ces courbes ne sont pas une science exacte étant donné les biais engendrés par le contenu des données mais donnent un aperçu global de la complétude des connaissances.
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- Parc amazonien de Guyane, 2026
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-- Le filtrage se passe dans la première requête "base":
-- 			- groupe taxonomique ajustable sur le contenu du champ "grp_taxonomique" (y caser group1_inpn, group2_inpn voire regne)
-- 			- Filtrage possible par regne ou groupe inpn
-- 			- Filtrage possible par secteur geographique
--				Sinon virer le lien vers ref_geo_l_areas qui ralentit l'exécution de la requête et la clause WHERE qui va avec
--				Pour ma part, j'ai ajouté des polygones de secteurs d'intérêt (id_type = 24) dans l_areas, que j'appelle pour faire des courbes d'accumulation. 
-- 				(Rappel: id_type = 24 = Unités géographiques permettant une orientation des prospections)
-----------------------------------------------------------------------------------------------------------------------------------------------------------

WITH base AS (
  -- Données de base : groupe taxo, espèce, jour, observers
  SELECT
    t.regne,
	t.group2_inpn AS grp_taxonomique, --> Modifier group1 ou group2 selon niveau souhaité
    t.cd_ref,
    s.date_min::date AS jour,
    s.observers
  FROM gn_synthese.synthese AS s
  JOIN taxonomie.taxref AS t
    ON t.cd_nom = s.cd_nom
  JOIN taxonomie.bib_taxref_rangs AS r
    ON r.id_rang = t.id_rang
  JOIN 	ref_geo.l_areas geo
	ON ST_INTERSECTS(s.the_geom_4326, geo.geom_4326)
  WHERE r.tri_rang >= 290 --> Tout ce qui est identifié à l'espèce ou infra (excluant les genres, familles, etc)
	--AND regne = 'Plantae'
	AND t.group2_inpn = 'Amphibiens'
	--AND t.group1_inpn = 'Trachéophytes'
	AND geo.area_code = 'Limonade'  --> A adapter pour des analyses par secteur ciblé
	--AND s.date_min >'1980-12-31'
),
jours_obs AS (
  -- Uniquement les jours où il y a eu au moins une obs pour le groupe
  SELECT DISTINCT regne, grp_taxonomique, jour
  FROM base
),
/* ===== Effort homme·jour (par groupe et par jour) ===== */
obs_split AS (
  -- On éclate le champ observers suivant les séparateurs , ; | &
  SELECT
  	b.regne, b.grp_taxonomique, 
    b.jour,
    regexp_split_to_table(COALESCE(b.observers, ''), '\s*(,|;|\||&)\s*') AS nom
  FROM base b
),
obs_clean AS (
  -- Normalisation des noms : trim + espaces uniques + minuscules
  SELECT
    regne, grp_taxonomique, 
    jour,
    lower(unaccent(regexp_replace(btrim(nom), '\s+', ' ', 'g'))) AS observateur
  FROM obs_split
  WHERE nom IS NOT NULL AND btrim(nom) <> ''
),
obs_uniques AS (
  -- Un observateur ne compte qu'une fois par jour et par groupe
  SELECT DISTINCT regne, grp_taxonomique, jour, observateur
  FROM obs_clean
),
flag_anonyme AS (
  -- +1 observateur anonyme si au moins une ligne du jour a observers NULL ou vide
  SELECT
    regne, grp_taxonomique, 
    jour,
    CASE WHEN bool_or(observers IS NULL OR btrim(observers) = '') THEN 1 ELSE 0 END AS a_ajouter_anonyme
  FROM base
  GROUP BY regne, grp_taxonomique,  jour
),
effort_par_jour AS (
  -- Effort homme·jour = nb d'observateurs nommés distincts + éventuel anonyme
  SELECT
    j.regne, j.grp_taxonomique, 
    j.jour,
    COALESCE(u.nb_nommes, 0) + COALESCE(f.a_ajouter_anonyme, 0) AS effort_homme_jour
  FROM jours_obs j
  LEFT JOIN (
    SELECT regne, grp_taxonomique, jour, COUNT(*) AS nb_nommes
    FROM obs_uniques
    GROUP BY regne, grp_taxonomique, jour
  ) u USING (regne, grp_taxonomique, jour)
  LEFT JOIN flag_anonyme f USING (regne, grp_taxonomique, jour)
),
/* ===== Richesse spécifique (par groupe et par jour) ===== */
first_seen AS (
  -- Premier jour d'observation pour chaque espèce (cd_ref) dans son groupe
  SELECT regne, grp_taxonomique,  cd_ref, MIN(jour) AS first_day
  FROM base
  GROUP BY regne, grp_taxonomique, cd_ref
),
new_species_by_day AS (
  -- Nouvelles espèces apparues chaque jour (par groupe)
  SELECT regne, grp_taxonomique,  first_day AS jour, COUNT(*) AS nouvelles_especes
  FROM first_seen
  GROUP BY regne, grp_taxonomique, first_day
),
jour_join AS (
  -- Base des jours observés, avec effort du jour et nouvelles espèces (0 si aucune)
  SELECT
    j.regne, j.grp_taxonomique, 
    j.jour,
    COALESCE(n.nouvelles_especes, 0) AS nouvelles_especes,
    COALESCE(e.effort_homme_jour, 0) AS effort_homme_jour
  FROM jours_obs j
  LEFT JOIN new_species_by_day n USING (regne, grp_taxonomique, jour)
  LEFT JOIN effort_par_jour e USING (regne, grp_taxonomique, jour)
),
cumuls AS (
  -- Cumuls par groupe au fil des jours
  SELECT
    regne, grp_taxonomique, 
    jour,
    SUM(nouvelles_especes) OVER (
      PARTITION BY grp_taxonomique
      ORDER BY jour
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS richesse_cumulee,
    SUM(1) OVER (
      PARTITION BY grp_taxonomique
      ORDER BY jour
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS jours_cumules,
    SUM(effort_homme_jour) OVER (
      PARTITION BY grp_taxonomique
      ORDER BY jour
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS effort_homme_jour_cumule
  FROM jour_join
)
SELECT
  regne, grp_taxonomique,
  jours_cumules           AS nombre_jours_cumules,
  effort_homme_jour_cumule,
  richesse_cumulee        AS nombre_especes_cumulees,
  ROW_NUMBER() OVER (PARTITION BY regne, grp_taxonomique ORDER BY jour) AS numero_jour,
  jour
FROM cumuls
ORDER BY regne, grp_taxonomique, jour;






/*
-----------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------										Autres scripts du genre... 								-------------------------------
-----------------------------									à retravailler pour filtrage/affinage						-------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------  Insertion d'un polygone d'intérêt dans l_areas
INSERT INTO ref_geo.l_areas(
		id_type, area_name, area_code, 
		geom, 
		centroid, 
		source, comment, enable, 
		geom_4326)
	VALUES (24, 'Mont Itoupé', 'Itoupe', 
		ST_PolygonFromText('Polygon((265228.67497426638146862 328673.76610450085718185, 262734.03056099923560396 330266.09232573525514454, 261566.32466542738256976 331699.18592484621331096, 260955.93294728751061484 332866.89182041800813749, 260929.39417693359428085 333981.52017528208671138, 261990.94499108986929059 335494.23008545476477593, 263052.4958052461151965 336608.85844031878514215, 263662.88752338598715141 337643.8704841211438179, 264671.36079683440038934 338652.34375756955705583, 266237.14824771485291421 339262.73547570942901075, 268307.17233531951205805 339156.5803942937636748, 269554.49454195308499038 338917.73146110860398039, 272155.294036635896191 338493.11113544611725956, 273216.84485079214209691 337962.33572836802341044, 274013.00796140928287059 337484.63786199770402163, 274782.63230167259462178 336157.69934430241119117, 274888.78738308814354241 334432.67927129846066236, 274092.62427247100276873 332336.11641333991428837, 273296.46116185380378738 330558.01879962818929926, 271651.05739991163136438 328700.30487485480261967, 269581.03331230697222054 328010.29684565321076661, 267219.08275080932071432 328063.37438636104343459, 265228.67497426638146862 328673.76610450085718185))', 2972),
		ST_centroid(ST_PolygonFromText('Polygon((265228.67497426638146862 328673.76610450085718185, 262734.03056099923560396 330266.09232573525514454, 261566.32466542738256976 331699.18592484621331096, 260955.93294728751061484 332866.89182041800813749, 260929.39417693359428085 333981.52017528208671138, 261990.94499108986929059 335494.23008545476477593, 263052.4958052461151965 336608.85844031878514215, 263662.88752338598715141 337643.8704841211438179, 264671.36079683440038934 338652.34375756955705583, 266237.14824771485291421 339262.73547570942901075, 268307.17233531951205805 339156.5803942937636748, 269554.49454195308499038 338917.73146110860398039, 272155.294036635896191 338493.11113544611725956, 273216.84485079214209691 337962.33572836802341044, 274013.00796140928287059 337484.63786199770402163, 274782.63230167259462178 336157.69934430241119117, 274888.78738308814354241 334432.67927129846066236, 274092.62427247100276873 332336.11641333991428837, 273296.46116185380378738 330558.01879962818929926, 271651.05739991163136438 328700.30487485480261967, 269581.03331230697222054 328010.29684565321076661, 267219.08275080932071432 328063.37438636104343459, 265228.67497426638146862 328673.76610450085718185))', 2972)),
		'PAG, service PNC', 'Polygone englobant les layons de prospection', true,  
		St_transform(ST_PolygonFromText('Polygon((265228.67497426638146862 328673.76610450085718185, 262734.03056099923560396 330266.09232573525514454, 261566.32466542738256976 331699.18592484621331096, 260955.93294728751061484 332866.89182041800813749, 260929.39417693359428085 333981.52017528208671138, 261990.94499108986929059 335494.23008545476477593, 263052.4958052461151965 336608.85844031878514215, 263662.88752338598715141 337643.8704841211438179, 264671.36079683440038934 338652.34375756955705583, 266237.14824771485291421 339262.73547570942901075, 268307.17233531951205805 339156.5803942937636748, 269554.49454195308499038 338917.73146110860398039, 272155.294036635896191 338493.11113544611725956, 273216.84485079214209691 337962.33572836802341044, 274013.00796140928287059 337484.63786199770402163, 274782.63230167259462178 336157.69934430241119117, 274888.78738308814354241 334432.67927129846066236, 274092.62427247100276873 332336.11641333991428837, 273296.46116185380378738 330558.01879962818929926, 271651.05739991163136438 328700.30487485480261967, 269581.03331230697222054 328010.29684565321076661, 267219.08275080932071432 328063.37438636104343459, 265228.67497426638146862 328673.76610450085718185))', 2972), 4326)
		);

--------------------------------------------------------------------------------------------------------------  Courbe d'accumulation par mois
WITH filtres AS (
  -- On limite aux taxons Amphibiens et aux rangs avec tri_rang >= 290
  SELECT
    s.cd_nom,
    s.date_min
  FROM gn_synthese.synthese AS s
  JOIN taxonomie.taxref AS t
    ON t.cd_nom = s.cd_nom
  JOIN taxonomie.bib_taxref_rangs AS r
    ON r.id_rang = t.id_rang
  WHERE t.group2_inpn = 'Amphibiens'
    AND r.tri_rang >= 290
	AND s.date_min > '1900-12-31'
),
first_seen AS (
  -- Mois de première observation pour chaque cd_nom filtré
  SELECT
    cd_nom,
    DATE_TRUNC('month', MIN(date_min))::date AS mois_premiere_obs
  FROM filtres
  GROUP BY cd_nom
),
monthly_new AS (
  -- Nombre de nouveaux cd_nom (premières apparitions) par mois
  SELECT
    mois_premiere_obs AS mois,
    COUNT(*) AS nouvelles_especes
  FROM first_seen
  GROUP BY mois_premiere_obs
),
calendar AS (
  -- Calendrier mensuel continu borné par les dates filtrées
  SELECT DATE_TRUNC('month', d)::date AS mois
  FROM generate_series(
    (SELECT DATE_TRUNC('month', MIN(date_min)) FROM filtres),
    (SELECT DATE_TRUNC('month', MAX(date_min)) FROM filtres),
    interval '1 month'
  ) AS g(d)
)
SELECT
  c.mois,
  COALESCE(mn.nouvelles_especes, 0) AS nouvelles_especes,
  SUM(COALESCE(mn.nouvelles_especes, 0)) OVER (ORDER BY c.mois) AS richesse_cumulee
FROM calendar c
LEFT JOIN monthly_new mn USING (mois)
ORDER BY c.mois;



--------------------------------------------------------------------------------------------------------------  Courbe d'accumulation par année
WITH filtres AS (
  SELECT s.cd_nom, s.date_min
  FROM gn_synthese.synthese AS s
  JOIN taxonomie.taxref AS t ON t.cd_nom = s.cd_nom
  JOIN taxonomie.bib_taxref_rangs AS r ON r.id_rang = t.id_rang
  WHERE t.group2_inpn = 'Amphibiens'
    AND r.tri_rang >= 290
),
first_seen AS (
  -- année de première observation par taxon
  SELECT
    cd_nom,
    EXTRACT(YEAR FROM MIN(date_min))::int AS annee_premiere_obs
  FROM filtres
  GROUP BY cd_nom
),
yearly_new AS (
  SELECT
    annee_premiere_obs AS annee,
    COUNT(*) AS nouvelles_especes
  FROM first_seen
  GROUP BY annee_premiere_obs
),
calendar AS (
  -- calendrier annuel continu, au format entier
  SELECT generate_series(
           (SELECT EXTRACT(YEAR FROM MIN(date_min))::int FROM filtres),
           (SELECT EXTRACT(YEAR FROM MAX(date_min))::int FROM filtres),
           1
         ) AS annee
)
SELECT
  c.annee,
  COALESCE(yn.nouvelles_especes, 0) AS nouvelles_especes,
  SUM(COALESCE(yn.nouvelles_especes, 0)) OVER (ORDER BY c.annee)
    AS richesse_cumulee
FROM calendar c
LEFT JOIN yearly_new yn USING (annee)
ORDER BY c.annee;

--------------------------------------------------------------------------------------------------------------  accumulation par nb de jours d'inventaire:
WITH filtres AS (
  -- On limite aux Amphibiens et aux rangs tri_rang >= 290
  SELECT s.cd_nom, s.date_min::date AS jour
  FROM gn_synthese.synthese AS s
  JOIN taxonomie.taxref AS t ON t.cd_nom = s.cd_nom
  JOIN taxonomie.bib_taxref_rangs AS r ON r.id_rang = t.id_rang
  WHERE t.group2_inpn = 'Amphibiens'
    AND r.tri_rang >= 290
	AND s.date_min >'1980-12-31'
),

jours_obs AS (
  -- Liste des jours où il existe au moins 1 observation filtrée
  SELECT DISTINCT jour
  FROM filtres
),

first_seen AS (
  -- Première observation par espèce
  SELECT cd_nom, MIN(jour) AS first_day
  FROM filtres
  GROUP BY cd_nom
),

daily_new AS (
  -- Nombre d'espèces "nouvelles" (premières apparitions) par jour observé
  SELECT
    jo.jour,
    COUNT(fs.cd_nom) AS nouvelles_especes
  FROM jours_obs jo
  LEFT JOIN first_seen fs ON fs.first_day = jo.jour
  GROUP BY jo.jour
),

final AS (
  -- Calcul de la richesse cumulée
  SELECT
    d.jour,
    d.nouvelles_especes,
    SUM(d.nouvelles_especes) OVER (ORDER BY d.jour) AS richesse_cumulee
  FROM daily_new d
)

SELECT
  ROW_NUMBER() OVER (ORDER BY jour) AS numero_jour,
  nouvelles_especes,
  richesse_cumulee,
  jour
FROM final
ORDER BY numero_jour;


--------------------------------------------------------------------------------------------------------------  Courbe d'accumulation d'effort d'inventaire
WITH filtres AS (
  -- Observations filtrées (Amphibiens + tri_rang >= 290)
  SELECT s.date_min::date AS jour
  FROM gn_synthese.synthese AS s
  JOIN taxonomie.taxref AS t ON t.cd_nom = s.cd_nom
  JOIN taxonomie.bib_taxref_rangs AS r ON r.id_rang = t.id_rang
  WHERE t.group2_inpn = 'Amphibiens'
    AND r.tri_rang >= 290	
	AND s.date_min >'1980-12-31'
),

jours_obs AS (
  -- Les jours avec au moins une observation
  SELECT DISTINCT jour
  FROM filtres
),

final AS (
  -- Ordre chronologique + cumul d’effort
  SELECT
    jour,
    1 AS effort_journalier,   -- 1 jour = 1 unité d’effort
    SUM(1) OVER (ORDER BY jour) AS effort_cumule
  FROM jours_obs
)

SELECT
  ROW_NUMBER() OVER (ORDER BY jour) AS numero_jour,
  effort_journalier,
  effort_cumule,
  jour
FROM final
ORDER BY jour;


*/