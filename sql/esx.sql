CREATE TABLE IF NOT EXISTS `mdt_data` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) DEFAULT NULL,
    `image` LONGTEXT DEFAULT NULL,
    `notes` LONGTEXT DEFAULT NULL,
    `officer_name` varchar(255) DEFAULT NULL,
    `timestamp` timestamp NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `mdt_bolos` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `title` varchar(50) DEFAULT NULL,
    `description` LONGTEXT DEFAULT NULL,
    `image` LONGTEXT DEFAULT NULL,
    `code` varchar(50) DEFAULT NULL,
    `officer_name` varchar(255) DEFAULT NULL,
    `timestamp` timestamp NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `mdt_incidents` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `title` varchar(50) DEFAULT NULL,
    `description` LONGTEXT DEFAULT NULL,
    `officer_involved` LONGTEXT DEFAULT NULL,
    `civilians_involved` LONGTEXT DEFAULT NULL,
    `evidence` LONGTEXT DEFAULT NULL,
    `officer_name` varchar(255) DEFAULT NULL,
    `timestamp` timestamp NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `mdt_logs` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) DEFAULT NULL,
    `action` varchar(255) DEFAULT NULL,
    `description` LONGTEXT DEFAULT NULL,
    `timestamp` timestamp NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `mdt_weapon_info` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) DEFAULT NULL,
    `serial` varchar(50) DEFAULT NULL,
    `weapon` varchar(50) DEFAULT NULL,
    `image` LONGTEXT DEFAULT NULL,
    `notes` LONGTEXT DEFAULT NULL,
    `timestamp` timestamp NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `mdt_clock` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) DEFAULT NULL,
    `officer_name` varchar(255) DEFAULT NULL,
    `clock_in_time` timestamp NULL DEFAULT NULL,
    `clock_out_time` timestamp NULL DEFAULT NULL,
    `total_time` int(11) DEFAULT 0,
    PRIMARY KEY (`id`)
);

-- Add indexes for better query performance
CREATE INDEX idx_mdt_data_identifier ON mdt_data(identifier);
CREATE INDEX idx_mdt_weapon_info_identifier ON mdt_weapon_info(identifier);
CREATE INDEX idx_mdt_weapon_info_serial ON mdt_weapon_info(serial);
CREATE INDEX idx_mdt_clock_identifier ON mdt_clock(identifier);
