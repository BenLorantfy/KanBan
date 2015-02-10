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
-- Adjusted time
--
SET @stationTime = 0;

--
-- Change this variable's value to make things faster or slower
-- (e.g. "2" twice as fast, "3" thrice as fast, "0.5" half as fast)
-- All times should be in seconds because the database engine doesn't like intervals less than 1
--
SET @time_stretch = 60;

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
	starting_stock_level INT
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
	
	-- Number of items in bin
	stock_level INT,
	
	-- Wether or not the tray has been picked up by the runner and is being replaced
	currently_replacing INT
);

--
-- Create
--
CREATE TABLE Station (
	id INT AUTO_INCREMENT PRIMARY KEY,
	workerId INT,
	completionDuration INT,
	startedTimeStamp INT
);

--
-- Sets delimiter to $$ temporarily
--
-- $$ is used to end the event statement
-- If we didn't do this, the sql inside the event with the regular delimiter would end the event statement
-- We don't have to use the special delimiter inside the event, because that sql isn't run immediatly, 
--	and the delimiter is changed back before it runs
--
DELIMITER $$

--
-- Runner checks if stock level is below 5 of any item
-- If it is so, the bin is marked as needing replacment and runner goes and fetches it (takes 5 minutes)
-- The runner also replaces any bins that were marked as needing replacment 5 minutes ago
--
CREATE EVENT checkBins
ON SCHEDULE EVERY 300 / @time_stretch SECOND
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
		Bin.stock_level = Item.starting_stock_level,
		Bin.currently_replacing = 0
	WHERE 
		Bin.currently_replacing = 1;
		
	--
	-- Check bins that are low (under 5 items) and tell runner to go get a replacment bin
	-- This is essentially marking the bin as needing replacment
	-- When the runner comes back, it refills the bins marked as needing replacmenet
	--
	UPDATE 
		Bin
	SET
		currently_replacing = 1
	WHERE
		stock_level <= @low_bin_stock;
END$$

--
-- Check if workers have completed a product
--
CREATE EVENT checkCompletion
ON SCHEDULE EVERY 1 SECOND
DO BEGIN
	-- Update station time
	SET @stationTime = @stationTime + @time_stretch;
	
	--
	-- Start a new product at each station that is done
	-- Essentially this means updating startedTimeStamp with current time
	-- TODO: Don't let station start again and don't create product if they're aren't enough items in bins
	--
	UPDATE 
		Station
	SET
		startedTimeStamp = @stationTime,
		completionDuration = 60
	WHERE
		startedTimeStamp + completionDuration >= @stationTime;
		
	--
	-- Decrease all bins by the number of stations completed, down to 0
	--
	UPDATE
		Bin
	SET
		stock_level = GREATEST(stock_level - ROW_COUNT(),0);
		
END$$

DELIMITER ;
