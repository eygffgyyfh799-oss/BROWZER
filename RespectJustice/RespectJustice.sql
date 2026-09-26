-- ════════════════════════════════════════════════════════════════════════════════
--  RespectJustice - قاعدة البيانات
--
--  ملاحظة: السكربت ينشئ هذي الجداول ويحدّثها تلقائياً عند التشغيل،
--  هذا الملف للي يبي يركّبها يدوياً (HeidiSQL / phpMyAdmin) قبل التشغيل.
--  آمن تشغيله أكثر من مرة (CREATE TABLE IF NOT EXISTS) وما يحذف أي بيانات.
-- ════════════════════════════════════════════════════════════════════════════════

-- سجل البصمة (دخول وخروج الدوام)
CREATE TABLE IF NOT EXISTS `justice_duty_history` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `duty_status` varchar(50) NOT NULL,
    `time` varchar(50) NOT NULL,
    `timestamp` bigint(20) NOT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- القضايا
CREATE TABLE IF NOT EXISTS `justice_reports` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `phone_number` varchar(20) NOT NULL,
    `report` text NOT NULL,
    `date` varchar(50) NOT NULL,
    `job` varchar(50) NOT NULL DEFAULT 'justice',
    `title` varchar(120) NOT NULL DEFAULT '',
    `case_type` varchar(50) NOT NULL DEFAULT '',
    `defendant_name` varchar(100) NOT NULL DEFAULT '',
    `defendant_citizenid` varchar(50) NOT NULL DEFAULT '',
    `witnesses` text NULL,
    `evidence` text NULL,
    `status` varchar(20) NOT NULL DEFAULT 'new',
    `handled_by` varchar(100) NOT NULL DEFAULT '',
    `submitter_info` longtext NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `job` (`job`),
    KEY `status` (`status`),
    KEY `defendant_citizenid` (`defendant_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ملاحظات الموظفين على القضايا
CREATE TABLE IF NOT EXISTS `justice_report_notes` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `report_id` int(11) NOT NULL,
    `author_citizenid` varchar(50) NOT NULL,
    `author_name` varchar(100) NOT NULL,
    `note` text NOT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `report_id` (`report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- العمليات المالية (تعويض / سحب)
CREATE TABLE IF NOT EXISTS `justice_transactions` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `officer_citizenid` varchar(50) NOT NULL,
    `officer_name` varchar(100) NOT NULL,
    `target_citizenid` varchar(50) NOT NULL,
    `target_name` varchar(100) NOT NULL,
    `amount` bigint(20) NOT NULL,
    `reason` varchar(255) NOT NULL,
    `date` varchar(50) NOT NULL,
    `type` varchar(30) NOT NULL DEFAULT 'compensation',
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `officer_citizenid` (`officer_citizenid`),
    KEY `target_citizenid` (`target_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- إيقاف الخدمات
CREATE TABLE IF NOT EXISTS `justice_suspensions` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `reason` varchar(255) NOT NULL,
    `officer_citizenid` varchar(50) NOT NULL,
    `officer_name` varchar(100) NOT NULL,
    `active` tinyint(1) NOT NULL DEFAULT 1,
    `lifted_by` varchar(100) NULL,
    `lifted_at` timestamp NULL DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- سجل كل عمليات موظفي العدل
CREATE TABLE IF NOT EXISTS `justice_logs` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `officer_citizenid` varchar(50) NOT NULL,
    `officer_name` varchar(100) NOT NULL,
    `action` varchar(50) NOT NULL,
    `target_citizenid` varchar(50) NULL,
    `target_name` varchar(100) NULL,
    `details` longtext NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `officer_citizenid` (`officer_citizenid`),
    KEY `target_citizenid` (`target_citizenid`),
    KEY `action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
