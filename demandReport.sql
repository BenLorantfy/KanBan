USE Kanban;
CREATE OR REPLACE VIEW Demand AS 
SELECT 
	 Station.id AS "Station"
	,CONCAT(Worker.last_name,",",Worker.first_name) AS "Worker"
	,Item.name AS "Item"
	,Bin.replacements AS "Demand (Number of replacements)"
FROM 
	Bin
JOIN
	Item
ON
	Bin.item_id = Item.id
LEFT JOIN
	Station
ON
	Bin.station_id = Station.id
JOIN
	Worker
ON
	Station.worker_id = Worker.id
ORDER BY
	Bin.replacements DESC, Station.id;
	
SELECT * FROM Demand;