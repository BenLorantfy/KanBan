USE Kanban;
CREATE OR REPLACE VIEW Defect AS 
SELECT 
	 Station.id AS "Station"
	,Lamp.test_unit_number AS "Lamp"
	,CONCAT(Worker.last_name,",",Worker.first_name) AS "Worker"
FROM 
	Lamp
LEFT JOIN
	Station
ON
	Lamp.station_id = Station.id
JOIN
	Worker
ON
	Station.worker_id = Worker.id
WHERE
	defected = true
ORDER BY
	Station.id, Lamp.test_unit_number;
	
SELECT * FROM Defect;