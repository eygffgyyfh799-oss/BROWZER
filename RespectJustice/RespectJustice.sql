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
    `undo_data` longtext NULL,
    `undone_by` varchar(100) NULL,
    `undone_at` timestamp NULL DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `officer_citizenid` (`officer_citizenid`),
    KEY `target_citizenid` (`target_citizenid`),
    KEY `action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- استدعاءات المحكمة
CREATE TABLE IF NOT EXISTS `justice_summons` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `reason` varchar(255) NOT NULL,
    `appointment` varchar(100) NOT NULL DEFAULT '',
    `location` varchar(100) NOT NULL DEFAULT '',
    `officer_citizenid` varchar(50) NOT NULL,
    `officer_name` varchar(100) NOT NULL,
    `status` varchar(20) NOT NULL DEFAULT 'pending',
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══ القضاء والشرطة: المشبوهين، الأوامر، طلبات الشرطة، المحامين، المستندات، الأحكام ═══
CREATE TABLE IF NOT EXISTS `justice_suspects` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `reason` varchar(255) NOT NULL,
    `danger` varchar(20) NOT NULL DEFAULT 'medium',
    `added_by` varchar(100) NOT NULL,
    `added_by_cid` varchar(50) NOT NULL,
    `active` tinyint(1) NOT NULL DEFAULT 1,
    `removed_by` varchar(100) NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `justice_warrants` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `type` varchar(20) NOT NULL,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `reason` varchar(255) NOT NULL,
    `place` varchar(150) NOT NULL DEFAULT '',
    `issued_by` varchar(100) NOT NULL,
    `issued_by_cid` varchar(50) NOT NULL,
    `requested_by` varchar(150) NOT NULL DEFAULT '',
    `status` varchar(20) NOT NULL DEFAULT 'active',
    `executed_by` varchar(150) NULL,
    `expires_at` timestamp NULL DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `justice_police_requests` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `type` varchar(30) NOT NULL,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `reason` varchar(255) NOT NULL,
    `details` varchar(255) NOT NULL DEFAULT '',
    `officer_cid` varchar(50) NOT NULL,
    `officer_name` varchar(100) NOT NULL,
    `officer_job` varchar(100) NOT NULL DEFAULT '',
    `officer_grade` varchar(100) NOT NULL DEFAULT '',
    `officer_callsign` varchar(50) NOT NULL DEFAULT '',
    `status` varchar(20) NOT NULL DEFAULT 'pending',
    `answered_by` varchar(100) NULL,
    `answer_note` varchar(255) NOT NULL DEFAULT '',
    `answered_at` timestamp NULL DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `status` (`status`),
    KEY `officer_cid` (`officer_cid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `justice_case_lawyers` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `report_id` int(11) NOT NULL,
    `lawyer_cid` varchar(50) NOT NULL,
    `lawyer_name` varchar(100) NOT NULL,
    `side` varchar(20) NOT NULL DEFAULT 'plaintiff',
    `assigned_by` varchar(100) NOT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `report_lawyer` (`report_id`, `lawyer_cid`),
    KEY `lawyer_cid` (`lawyer_cid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `justice_case_documents` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `report_id` int(11) NOT NULL,
    `author_cid` varchar(50) NOT NULL,
    `author_name` varchar(100) NOT NULL,
    `author_role` varchar(20) NOT NULL DEFAULT 'justice',
    `title` varchar(120) NOT NULL,
    `content` text NOT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `report_id` (`report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `justice_verdicts` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `report_id` int(11) NULL,
    `citizenid` varchar(50) NOT NULL,
    `name` varchar(100) NOT NULL,
    `type` varchar(20) NOT NULL,
    `amount` bigint(20) NOT NULL DEFAULT 0,
    `target_citizenid` varchar(50) NOT NULL DEFAULT '',
    `plate` varchar(15) NOT NULL DEFAULT '',
    `months` int(11) NOT NULL DEFAULT 0,
    `text` varchar(500) NOT NULL DEFAULT '',
    `dest` varchar(100) NOT NULL DEFAULT '',
    `judge_cid` varchar(50) NOT NULL,
    `judge_name` varchar(100) NOT NULL,
    `status` varchar(20) NOT NULL DEFAULT 'active',
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`),
    KEY `report_id` (`report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ═══ القسم المالي للقطاعات (الخزينة الداخلية + سجل العمليات) ═══
CREATE TABLE IF NOT EXISTS `justice_sector_funds` (
    `job` varchar(50) NOT NULL,
    `balance` bigint(20) NOT NULL DEFAULT 0,
    PRIMARY KEY (`job`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `justice_sector_transactions` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `job` varchar(50) NOT NULL,
    `type` varchar(20) NOT NULL,
    `amount` bigint(20) NOT NULL,
    `reason` varchar(150) NOT NULL,
    `officer_cid` varchar(50) NOT NULL,
    `officer_name` varchar(100) NOT NULL,
    `officer_grade` varchar(100) NOT NULL DEFAULT '',
    `balance_after` bigint(20) NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `job` (`job`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
