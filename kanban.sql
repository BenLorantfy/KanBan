--
-- Drop the database if it already exists
--

DROP DATABASE IF EXISTS KanBan;

--
-- Create database and use it
--

CREATE DATABASE KanBan;
USE KanBan;

--
-- Change this variable's value to make things faster or slower
-- (e.g. "2" twice as fast, "3" thrice as fast, "0.5" half as fast)
-- All times should be in seconds because the database engine doesn't like intervals less than 1
--
SET @time_stretch = 4;

--
-- This constant stores the maximum number of items a bin needs to be replaced
--

SET @low_bin_stock = 5;

--
-- Enable events
--

SET GLOBAL event_scheduler = ON;

--
-- Create item table
--

CREATE TABLE Item (
	id INT AUTO_INCREMENT PRIMARY KEY,
	
	name VARCHAR(30),
	
	-- Starting stock level
	default_stock_level INT
);

--
-- Create bin table
-- Keeps track of what type of item is in bin, and how many of that item are in it
-- Also has a flag to indicate wether or not the runner is currently replacing it (takes 5 minutes)
--

CREATE TABLE Bin(
	id INT AUTO_INCREMENT PRIMARY KEY,
	
	-- Id of item the bin contains

	item_id INT,
	
	-- Station bin belongs to
	station_id INT,
	
	-- Number of items in bin

	stock_level INT,
	
	-- Wether or not the tray has been picked up by the runner and is being replaced
	currently_replacing BOOL
);

--
-- Create
--

CREATE TABLE Station (
	id INT AUTO_INCREMENT PRIMARY KEY,
	worker_id INT,
	timeToFinish INT
);

--
-- Create test tray table
-- Keeps track of test trays where worker put their completed lamps in.
-- Has a capacity indicating how many items can be storred in the tray
--

CREATE TABLE Tray(
	id INT AUTO_INCREMENT PRIMARY KEY,
	
	-- How many items can tray fit

	capacity INT
);

--
-- Create lamp table
-- Keeps track of all completed lamps
-- Has id of a tray where it is storred in, and id of a station where it was assembled
-- Also, has a bool indicating if lamp if defected or not
--

CREATE TABLE Lamp(
	testUnitNumber VARCHAR(10) PRIMARY KEY,
	
	-- id of a tray where lamp is storred

	trayId INT,
	
	-- id of a station where lamp was assembled

	stationId INT,

	-- is item defected or not

	defected BOOL
);

--
-- Create worker table
-- Keeps track of all workers working on assembly line
-- Each worker has a specific experience level
-- Also, each worker has a time to finish his job. If time is < 0, worker is not working right now 
--

CREATE TABLE Worker(
	id INT AUTO_INCREMENT PRIMARY KEY,
	
	--
	-- Regular workers efficiency is 1
	-- New workers efficiency is 1.5
	-- Super experienced workers efficiency is 0.85
	-- Lower number is better efficency
	--


	efficiency DOUBLE,

	defect_rate DOUBLE
);

--
-- Sets delimiter to $$ temporarily
--
-- $$ is used to end the event statement
-- If we didn't do this, the sql inside the event with the regular delimiter would end the event statement
-- We don't have to use the special delimiter inside the event, because that sql isn't run immediatly, 
-- and the delimiter is changed back before it runs
--

DELIMITER $$

--
-- Runner checks if stock level is below 5 of any item
-- If it is so, the bin is marked as needing replacment and runner goes and fetches it (takes 5 minutes)
-- The runner also replaces any bins that were marked as needing replacment 5 minutes ago
--

CREATE EVENT checkBins
ON SCHEDULE EVERY 300 / 10 SECOND
DO BEGIN

	--
	-- Replace low bins marked 5 minutes ago with arrived full bins
	-- This is essentially setting the bin's stock level to full
	--

	UPDATE 
		Bin 
	JOIN
		Item
	ON
		Bin.item_id = Item.id
	SET 
		Bin.stock_level = Bin.stock_level + Item.default_stock_level,
		Bin.currently_replacing = FALSE
	WHERE 
		Bin.currently_replacing = TRUE;
		
	--
	-- Check bins that are low (under 5 items) and tell runner to go get a replacment bin
	-- This is essentially marking the bin as needing replacment
	-- When the runner comes back, it refills the bins marked as needing replacmenet
	--

	UPDATE 
		Bin
	SET
		currently_replacing = TRUE
	WHERE
		stock_level <= 5;
END$$


--
-- Check if workers have completed a product
--

CREATE EVENT checkCompletion
ON SCHEDULE EVERY 1 SECOND
DO BEGIN
	--
	-- Decrease each worker's timeToFinish
	--

	UPDATE 
		Station
	SET
		timeToFinish = timeToFinish - 10
	WHERE
		timeToFinish > 0;
		
	-- Reset station completion time for stations that are done
	-- Decrease stock level in bins by 1
	--

	UPDATE
		Station
	JOIN
		Worker
	ON
		Station.worker_id = Worker.id
	SET
		-- Generates a new timeToFinish based on worker efficency and a random element
		Station.timeToFinish = 60 * Worker.efficiency * (0.9 + RAND() * 0.2) + Station.timeToFinish
	WHERE
		Station.timeToFinish <= 0 AND 
		(SELECT MIN(stock_level) FROM Bin WHERE Bin.station_id = Station.id) > 0;
		
END$$

--
-- Trigger calls upon attempt to add finished lamp into tray
-- This trigger generates correct testUnitNumber and chooses a Tray to put in
-- If Tray is full new tray is created
--

CREATE TRIGGER putIntoTray
BEFORE INSERT
ON Lamp
FOR EACH ROW
	BEGIN
		-- If last tray has 60+ items

		IF ((SELECT COUNT(*) FROM Lamp WHERE Lamp.trayID = (SELECT MAX(id) FROM Tray)) >= 60)
		THEN
			-- Add a new tray of default capacity
			INSERT INTO Tray (capacity) VALUES (60);
		END IF;

		-- Generate unit test number (big scarry function)
		SET NEW.testUnitNumber = CONCAT('FL', (SELECT LPAD((SELECT MAX(id) FROM Tray), 6, '0')), 
											  (SELECT LPAD((SELECT COUNT(*) FROM Lamp WHERE Lamp.trayID = (SELECT MAX(id) FROM Tray)), 2, '0')));
		-- Insert into the last tray
		SET NEW.trayID = (SELECT MAX(id) FROM Tray);
END$$

--
-- Trigger calls upon attempt to update Station
-- This trigger generates defect status and inserts a new lamp
-- Also, it takes new items from bins
--

CREATE TRIGGER newLamp
AFTER UPDATE
ON Station
FOR EACH ROW
	BEGIN
		DECLARE dice DOUBLE;	-- dice for random
		DECLARE defected BOOL;	-- defect status variable

		IF (NEW.timeToFinish <= 0) THEN		-- do work only if work is finished
			SET dice := RAND() * 100;		-- Throw a dice from 0 to 100
			
			-- if received value is less than defect rate than there is a defect
			IF (dice > (SELECT defect_rate FROM Worker WHERE Worker.id = NEW.worker_id)) THEN
				SET defected := false;
			ELSE
				SET defected := true;
			END IF;

			-- insert new lamp. We don't care about testUnitNumber and Tray number since they are going to be generated
			INSERT INTO Lamp (testUnitNumber, trayId, stationId, defected) VALUES ('1', 0, NEW.id, defected);

			-- take one item from each bin
			UPDATE 
				Bin
			SET
				Bin.stock_level = Bin.stock_level - 1
			WHERE
				Bin.station_id = NEW.id;
		END IF;
END$$

DELIMITER ;

INSERT INTO Tray (capacity) VALUES (60);

INSERT INTO Item (name, default_stock_level)  VALUES ('Harness', 55);
INSERT INTO Item (name, default_stock_level)  VALUES ('Rflector', 35);
INSERT INTO Item (name, default_stock_level)  VALUES ('Housing', 24);
INSERT INTO Item (name, default_stock_level)  VALUES ('Lens', 40);
INSERT INTO Item (name, default_stock_level)  VALUES ('Bulb', 60);
INSERT INTO Item (name, default_stock_level)  VALUES ('Bezel', 75);

INSERT INTO Worker(efficiency, defect_rate) VALUES (1, 0.5);
INSERT INTO Worker(efficiency, defect_rate) VALUES (0.85, 0.15);
INSERT INTO Worker(efficiency, defect_rate) VALUES (1.5, 0.85);

INSERT INTO Station(worker_id, timeToFinish) VALUES (1, 60);
INSERT INTO Station(worker_id, timeToFinish) VALUES (2, 60);
INSERT INTO Station(worker_id, timeToFinish) VALUES (3, 60);

INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (1, 1, 55, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (2, 1, 35, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (3, 1, 24, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (4, 1, 40, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (5, 1, 60, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (6, 1, 75, false);

INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (1, 2, 55, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (2, 2, 35, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (3, 2, 24, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (4, 2, 40, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (5, 2, 60, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (6, 2, 75, false);

INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (1, 3, 55, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (2, 3, 35, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (3, 3, 24, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (4, 3, 40, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (5, 3, 60, false);
INSERT INTO Bin(item_id, station_id, stock_level, currently_replacing) VALUES (6, 3, 75, false);