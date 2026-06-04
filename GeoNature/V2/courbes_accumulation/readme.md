# Complétude des inventaires et courbes d'accumulation

## Contexte

Si la capitalisation des connaissances est une nécessité indéniable, elle sert notamment à réaliser des états des lieux sur des territoires et des groupes taxonomiques identifiés. 
Une fois l'inventaire atteignant une certaine exhaustivité, les naturalistes et gestionnaires peuvent entrer dans une phase de suivi ou de gestion. Mais comment savoir si les efforts d'inventaires sont "complets" et ont permis d'atteindre un seuil de connaissance représentatif ? 

Les naturalistes utilisent un outil simple: la courbe d'accumulation. A chaque jour d'inventaire, ils comptabilisent le nombre d'espèces. Aux premiers jours, le nombre d'espèce augmente rapidement car les espèces les plus communes sont inventoriées. Puis le nombre d'espèce augmente de moins en moins vite au fur et à mesure de l'identification d'espèces de plus en plus rares/occasionnelles. Si l'exhasutivité de l'inventaire est atteinte, le nombre d'espèce reste constant, à son maximum... Jusqu'à ce qu'un furieux fasse une trouvaille qui va secouer le tissus de spécialistes mais pas les statistiques.

En représentant ces données sur une courbe représentant le nombre d'espèces en fonction du nombre de jours d'inventaire, cette complétude saute aux yeux. La courbe atteint-elle un seuil? Si oui, félicitations! Sinon, il y a encore à faire... (pour plus d'informations sur les courbes d'accumulation, interrogez vos chargés de mission faune/flore/fonge ou votre moteur de recherche préféré!)

Si la biostatistique "lourde" reste la meilleure solution pour examiner cette complétude et avoir des estimations robustes, il est également possible de mobiliser simplement votre GeoNature et les graphiques d'un tableur.
GeoNature permet de bancariser les données, de les structurer, d'avoir quelques indicateurs (tableau de bord) et de visualiser nos données brutes mais pas de visualiser ces courbes d'accumulation. Mais, à défaut d'être un expert sous R, il y a une astuce : le module d'export!

## Processus

Option préalable mais permettant de cibler et de réitérer vos analyses: intégrer vos zones d'études parmis les objets de ref_geo.l_areas

1. Dans pgAdmin : créer une à plusieurs vues permettant de synthétiser les données de synthèse (cf. Données sources)
2. Dans GeoNature > Administration > Export > Exports : créer un à plusieurs exports sur la base de cette/ces vue/s
3. Dans Excel/Calc: chargez les données issues de cet export et réalisez vos courbes pour chaque groupe taxonomique.

## Données sources

`courbe_a_accumulation_par_groupe_taxo.sql` : Ce script permet de sortir les données suivantes pour les reporter directement dans un graphique:
- regne
- group1_inpn (ou group2_inpn)  (seuls les taxons précis à l'espèce ou à des rangs plus précis - sous-espèce, etc - sont pris en compte)
- nombre_jours_cumules
- effort_homme_jour_cumule (en splitant le champ "observers")
- nombre_especes_cumulees
- numero_jour + jour

La sous-requête `base` permet de filtrer:
- groupe taxonomique ajustable sur le contenu du champ "grp_taxonomique" (affinez selon group1_inpn, group2_inpn voire regne)
- filtrage possible par regne ou groupe inpn
- filtrage possible par secteur geographique (Sinon supprimez le lien vers ref_geo_l_areas qui ralentit l'exécution de la requête et la clause WHERE qui va avec)
- filtrage des données invalides, d'absence, etc.

Pour ma part, j'ai intégré à ref_geo.l_areas des polygones de secteurs d'intérêt (id_type = 24), que j'appelle pour faire des courbes d'accumulation. (Rappel: id_type = 24 = Unités géographiques permettant une orientation des prospections)

## Pour aller plus loin
Dans un bloc commenté en fin de script, vous trouverez des requeêtes sources pour des extractions par mois, années, etc. A vous de jouer!
Si certains souhaitent corriger et compléter ce script, vous êtes les bienvenus! 

Et pourquoi pas sortir directement la valeur seuil et donc le % de connaissance sur la zone géographique?
Affaire à suivre...
