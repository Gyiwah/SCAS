/* ============================================================================
   SCAS - FILE 10 : SEED DATA
   ---------------------------------------------------------------------------
   Two kinds of data are loaded here.

   REFERENCE DATA (settings, roles, schools, terms, holidays) - this is real
   configuration the system needs in order to run at all.

   DEMONSTRATION DATA (staff, timetable, a full term of attendance history) -
   a realistic pilot at a Ghanaian Senior High School. The history is
   generated procedurally rather than written out as INSERT statements for
   three reasons: it produces enough rows for the query plans in file 11 to be
   meaningful, the attendance is created through the real triggers so it is
   guaranteed to obey every business rule, and the absences are produced by
   calling the real sp_mark_absentees rather than by faking them.

   PASSWORDS for the demonstration accounts are documented in README.md.
   ========================================================================= */

SET NAMES utf8mb4;
USE scas_db;

/* ###########################################################################
   1. RUNTIME CONFIGURATION
   Loaded first: the stored functions read these, so nothing else works
   correctly until they exist.
   ######################################################################### */
INSERT INTO system_setting (setting_key, setting_value, data_type, description) VALUES
('attendance.grace_minutes',        '10',  'INT',     'Minutes after the bell still counted as Present'),
('qr.validity_minutes',             '30',  'INT',     'How long a generated QR code remains scannable'),
('security.max_failed_logins',      '5',   'INT',     'Failed logins before the account locks'),
('security.lockout_minutes',        '15',  'INT',     'How long an account stays locked'),
('security.event_retention_days',   '180', 'INT',     'Retention period for INFO security events'),
('security.session_timeout_minutes','30',  'INT',     'Idle timeout for an application session'),
('leave.max_backdate_days',         '7',   'INT',     'How far back a leave request may be dated'),
('report.slow_query_ms',            '200', 'INT',     'Statements slower than this are logged for the DBA'),
('app.name',        'Smart Classroom Attendance System', 'STRING', 'Application display name'),
('app.institution', 'University of Education, Winneba',  'STRING', 'Owning institution'),
('app.academic_year','2025/2026', 'STRING', 'Academic year currently in use');

/* ###########################################################################
   2. ROLES
   privilege_level is the number every authorisation check compares against.
   ######################################################################### */
INSERT INTO user_role (role_id, role_name, description, privilege_level) VALUES
(1, 'Teacher',              'Checks in by scanning a QR code; views own records only', 10),
(2, 'Headteacher',          'Whole-school visibility; approves leave; issues QR codes', 50),
(3, 'School Administrator', 'Manages staff accounts and the timetable for one school',  90),
(4, 'System Administrator', 'Full control across all schools; database administration', 99);

/* ###########################################################################
   3. SCHOOLS
   ######################################################################### */
INSERT INTO school (school_id, school_code, school_name, district, region, address, phone_number, email) VALUES
(1, 'GES-CR-0142', 'Winneba Senior High School', 'Effutu Municipal', 'Central',
    'P.O. Box 217, Winneba', '0332 722 145', 'info@winnebashs.edu.gh'),
(2, 'GES-GA-0088', 'Accra Academy', 'Accra Metropolitan', 'Greater Accra',
    'P.O. Box 561, Bubuashie, Accra', '0302 228 471', 'admin@accraacademy.edu.gh');

/* ###########################################################################
   4. ACADEMIC TERMS
   One current term per school (enforced by trg_academic_term_bi), plus a
   closed previous term so reports can be filtered by term.
   ######################################################################### */
INSERT INTO academic_term (term_id, school_id, term_name, academic_year, start_date, end_date, is_current) VALUES
(1, 1, '2025/2026 Term 2', '2025/2026', '2026-01-12', '2026-04-10', 0),
(2, 1, '2025/2026 Term 3', '2025/2026', '2026-05-04', '2026-08-28', 1),
(3, 2, '2025/2026 Term 3', '2025/2026', '2026-05-04', '2026-08-28', 1);

/* ###########################################################################
   5. HOLIDAYS
   NULL school_id = national holiday, applies everywhere.
   ######################################################################### */
INSERT INTO holiday (school_id, holiday_date, description) VALUES
(NULL, '2026-05-01', 'May Day'),
(NULL, '2026-07-01', 'Republic Day'),
(NULL, '2026-08-04', 'Founders Day'),
(1,    '2026-06-15', 'Winneba SHS Speech and Prize-Giving Day'),
(1,    '2026-07-20', 'Aboakyer Festival - school closed'),
(2,    '2026-06-26', 'Accra Academy Founders Week');

/* ###########################################################################
   6. CLASSROOMS
   ######################################################################### */
INSERT INTO classroom (classroom_id, school_id, room_name, building, capacity) VALUES
(1, 1, 'Room A1', 'Block A', 45),
(2, 1, 'Room A2', 'Block A', 45),
(3, 1, 'Room A3', 'Block A', 40),
(4, 1, 'Room B1', 'Block B', 50),
(5, 1, 'Room B2', 'Block B', 50),
(6, 1, 'Room B3', 'Block B', 40),
(7, 1, 'Science Laboratory 1', 'Science Block', 35),
(8, 1, 'ICT Laboratory',       'Science Block', 30),
(9, 1, 'Room C1', 'Block C', 45),
(10, 2, 'Room 1', 'Main Block', 48),
(11, 2, 'Room 2', 'Main Block', 48),
(12, 2, 'ICT Centre', 'Annex', 32);

/* ###########################################################################
   7. USERS AND TEACHERS
   password_hash values are real bcrypt hashes; see README.md for the
   plaintext demonstration passwords. must_change_password is 0 here only so
   the demonstration accounts can be used immediately - sp_create_user sets it
   to 1 for every account created through the application.
   ######################################################################### */

/* --- administrative accounts --------------------------------------------- */
INSERT INTO app_user (user_id, full_name, username, password_hash, role_id, school_id, phone_number, email, must_change_password) VALUES
(1, 'Dr. Nana Adjei-Boateng', 'sysadmin', '$2y$10$pcqDP8rZgGQoLIA9pbBoKegURTu1cgJf.j0zjNVeh1yph4FgaGtrS', 4, NULL, '0244000001', 'sysadmin@scas.edu.gh', 0),
(2, 'Mr. Joseph Ntim Baah',   'head.winneba', '$2y$10$ivlAfC9tDFZW58NwLnVhGelSUOz7Z2B2F9yUqLRcxxHglm/BGzS0C', 2, 1, '0244000002', 'head@winnebashs.edu.gh', 0),
(3, 'Mrs. Vida Otoo',         'admin.winneba', '$2y$10$CGJxbm7itra85eWET58rZev3X31Z0/azC8oMMZOsEcNXyEeZzKcIW', 3, 1, '0244000003', 'registry@winnebashs.edu.gh', 0),
(4, 'Mr. Charles Nii Armah',  'head.accra', '$2y$10$ivlAfC9tDFZW58NwLnVhGelSUOz7Z2B2F9yUqLRcxxHglm/BGzS0C', 2, 2, '0244000004', 'head@accraacademy.edu.gh', 0);

/* --- teaching staff, Winneba SHS ----------------------------------------- */
INSERT INTO app_user (user_id, full_name, username, password_hash, role_id, school_id, phone_number, email, must_change_password) VALUES
(11, 'Kwame Mensah',      'k.mensah',   '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100011', 'k.mensah@winnebashs.edu.gh', 0),
(12, 'Akosua Boateng',    'a.boateng',  '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100012', 'a.boateng@winnebashs.edu.gh', 0),
(13, 'Yaw Owusu',         'y.owusu',    '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100013', 'y.owusu@winnebashs.edu.gh', 0),
(14, 'Efua Danquah',      'e.danquah',  '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100014', 'e.danquah@winnebashs.edu.gh', 0),
(15, 'Kofi Asante',       'k.asante',   '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100015', 'k.asante@winnebashs.edu.gh', 0),
(16, 'Ama Adjei',         'am.adjei',   '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100016', 'am.adjei@winnebashs.edu.gh', 0),
(17, 'Kwabena Nyarko',    'kw.nyarko',  '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100017', 'kw.nyarko@winnebashs.edu.gh', 0),
(18, 'Abena Frimpong',    'ab.frimpong','$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100018', 'ab.frimpong@winnebashs.edu.gh', 0),
(19, 'Emmanuel Tetteh',   'em.tetteh',  '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100019', 'em.tetteh@winnebashs.edu.gh', 0),
(20, 'Grace Amoah',       'g.amoah',    '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100020', 'g.amoah@winnebashs.edu.gh', 0),
(21, 'Samuel Quartey',    's.quartey',  '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100021', 's.quartey@winnebashs.edu.gh', 0),
(22, 'Hannah Appiah',     'h.appiah',   '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 1, '0244100022', 'h.appiah@winnebashs.edu.gh', 0);

/* --- teaching staff, Accra Academy ---------------------------------------- */
INSERT INTO app_user (user_id, full_name, username, password_hash, role_id, school_id, phone_number, email, must_change_password) VALUES
(31, 'Isaac Darko',       'i.darko',    '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 2, '0244100031', 'i.darko@accraacademy.edu.gh', 0),
(32, 'Mavis Ofori',       'm.ofori',    '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 2, '0244100032', 'm.ofori@accraacademy.edu.gh', 0),
(33, 'Daniel Agyeman',    'd.agyeman',  '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 2, '0244100033', 'd.agyeman@accraacademy.edu.gh', 0),
(34, 'Comfort Sarpong',   'c.sarpong',  '$2y$10$LjFap.tmsCZW5wK.A9og.uVMHFDCqlwB.vJb/Z2S4KyCCHZ7pqOtm', 1, 2, '0244100034', 'c.sarpong@accraacademy.edu.gh', 0);

INSERT INTO teacher (teacher_id, user_id, staff_number, department, qualification, date_employed) VALUES
(1,  11, 'GES/2014/04121', 'Science',        'MSc Physics',              '2014-09-01'),
(2,  12, 'GES/2016/05233', 'Mathematics',    'BSc Mathematics, PGDE',    '2016-01-11'),
(3,  13, 'GES/2012/03110', 'Languages',      'MA English',               '2012-09-03'),
(4,  14, 'GES/2018/06744', 'Social Studies', 'BA Social Studies',        '2018-09-10'),
(5,  15, 'GES/2019/07120', 'Science',        'BSc Chemistry, PGDE',      '2019-01-14'),
(6,  16, 'GES/2015/04890', 'Mathematics',    'BEd Mathematics',          '2015-09-07'),
(7,  17, 'GES/2020/08341', 'ICT',            'BSc Computer Science',     '2020-09-01'),
(8,  18, 'GES/2013/03775', 'Languages',      'BA French, PGDE',          '2013-09-02'),
(9,  19, 'GES/2017/06012', 'Social Studies', 'BEd Social Studies',       '2017-09-04'),
(10, 20, 'GES/2021/09115', 'ICT',            'MSc Information Systems',  '2021-09-06'),
(11, 21, 'GES/2011/02556', 'Business',       'BCom, PGDE',               '2011-09-05'),
(12, 22, 'GES/2022/10233', 'Business',       'BSc Accounting',           '2022-09-05'),
(13, 31, 'GES/2015/04711', 'Science',        'BSc Biology, PGDE',        '2015-09-07'),
(14, 32, 'GES/2018/06655', 'Mathematics',    'BEd Mathematics',          '2018-09-10'),
(15, 33, 'GES/2014/04002', 'Languages',      'MA Ghanaian Languages',    '2014-09-01'),
(16, 34, 'GES/2019/07533', 'ICT',            'BSc Computer Engineering', '2019-01-14');

/* ###########################################################################
   8. TIMETABLE GENERATION
   Built by a procedure rather than by hand so that the clash-prevention
   triggers are exercised on every row, and so the grid is provably free of
   double-bookings.

   The assignment rule: teacher i teaches once per day, in period
   ((i + day) MOD 5) + 1, in room (i MOD room_count) + 1.
     - No teacher clash: each teacher has exactly one session per day.
     - No room clash: two teachers share a room only when their indexes differ
       by room_count, and that same difference shifts their period by
       (room_count MOD 5) != 0, so they are never in it at the same time.
   ######################################################################### */

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_seed_timetable $$
CREATE PROCEDURE sp_seed_timetable(
        IN p_school_id  INT UNSIGNED,
        IN p_term_id    SMALLINT UNSIGNED,
        IN p_first_teacher INT UNSIGNED,
        IN p_teacher_count INT,
        IN p_first_room INT UNSIGNED,
        IN p_room_count INT)
MODIFIES SQL DATA
BEGIN
    DECLARE i        INT DEFAULT 0;
    DECLARE d        INT DEFAULT 0;
    DECLARE v_period INT;
    DECLARE v_day    VARCHAR(10);
    DECLARE v_start  TIME;
    DECLARE v_end    TIME;
    DECLARE v_dept   VARCHAR(60);
    DECLARE v_subject VARCHAR(60);
    DECLARE v_group  VARCHAR(30);

    WHILE i < p_teacher_count DO
        SELECT department INTO v_dept FROM teacher WHERE teacher_id = p_first_teacher + i;

        SET v_subject = CASE v_dept
            WHEN 'Science'        THEN ELT(1 + (i MOD 3), 'Integrated Science', 'Physics', 'Chemistry')
            WHEN 'Mathematics'    THEN ELT(1 + (i MOD 2), 'Core Mathematics', 'Elective Mathematics')
            WHEN 'Languages'      THEN ELT(1 + (i MOD 3), 'English Language', 'Literature in English', 'French')
            WHEN 'Social Studies' THEN ELT(1 + (i MOD 3), 'Social Studies', 'Government', 'History')
            WHEN 'ICT'            THEN ELT(1 + (i MOD 2), 'Information Technology', 'Computing')
            WHEN 'Business'       THEN ELT(1 + (i MOD 3), 'Financial Accounting', 'Business Management', 'Economics')
            ELSE 'General Studies' END;

        SET d = 0;
        WHILE d < 5 DO
            SET v_day = ELT(d + 1, 'Monday','Tuesday','Wednesday','Thursday','Friday');
            SET v_period = ((i + d) MOD 5) + 1;

            SET v_start = ELT(v_period, '07:30:00','08:40:00','10:10:00','11:20:00','13:10:00');
            SET v_end   = ELT(v_period, '08:40:00','09:50:00','11:20:00','12:30:00','14:20:00');
            SET v_group = CONCAT('SHS ', 1 + ((i + d) MOD 3), ' ',
                                 ELT(1 + (i MOD 4), 'Science', 'Arts', 'Business', 'General'),
                                 ' ', CHAR(65 + (i MOD 2)));

            INSERT INTO timetable (teacher_id, classroom_id, term_id, subject, class_group,
                                   day_of_week, start_time, end_time)
            VALUES (p_first_teacher + i,
                    p_first_room + (i MOD p_room_count),
                    p_term_id, v_subject, v_group, v_day, v_start, v_end);
            SET d = d + 1;
        END WHILE;
        SET i = i + 1;
    END WHILE;
END $$

/* ---------------------------------------------------------------------------
   sp_seed_history - generates a term of attendance.
   For each teaching day in the range, for each scheduled session:
     - 88% of the time a QR code is issued and scanned; of those scans about
       one in seven is late enough to be marked Late by the real trigger.
     - the remaining 12% are left with no scan at all, and are then resolved
       by calling the production sp_mark_absentees for that date.
   Nothing here inserts a status directly: every verdict is computed by
   trg_attendance_bi, exactly as it would be in live use.
   ------------------------------------------------------------------------ */
DROP PROCEDURE IF EXISTS sp_seed_history $$
CREATE PROCEDURE sp_seed_history(
        IN p_from DATE,
        IN p_to   DATE)
MODIFIES SQL DATA
BEGIN
    DECLARE v_date      DATE;
    DECLARE v_done      TINYINT DEFAULT 0;
    DECLARE v_tt        INT UNSIGNED;
    DECLARE v_teacher   INT UNSIGNED;
    DECLARE v_start     TIME;
    DECLARE v_school    INT UNSIGNED;
    DECLARE v_qr        INT UNSIGNED;
    DECLARE v_offset    INT;
    DECLARE v_scan      DATETIME;
    DECLARE v_absent    INT;
    DECLARE v_excused   INT;

    DECLARE cur CURSOR FOR
        SELECT tt.timetable_id, tt.teacher_id, tt.start_time, c.school_id
        FROM timetable tt
        JOIN classroom c ON c.classroom_id = tt.classroom_id
        WHERE tt.is_active = 1
          AND tt.day_of_week = DAYNAME(v_date);
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    SET v_date = p_from;

    WHILE v_date <= p_to DO
        IF DAYOFWEEK(v_date) NOT IN (1, 7) THEN      /* skip Sunday and Saturday */
            SET v_done = 0;
            OPEN cur;
            day_loop: LOOP
                FETCH cur INTO v_tt, v_teacher, v_start, v_school;
                IF v_done = 1 THEN
                    LEAVE day_loop;
                END IF;

                /* A teacher on approved leave does not turn up and does not
                   scan. Leaving the session unscanned is what lets
                   sp_mark_absentees classify it as Excused rather than
                   Absent - the behaviour proposal problem 4 asks for. */
                IF fn_is_holiday(v_school, v_date) = 0
                   AND fn_is_on_leave(v_teacher, v_date) = 0
                   AND RAND() < 0.88 THEN
                    /* Issue the code for that session, back-dated to the day. */
                    INSERT INTO qr_code (timetable_id, code_value, session_date,
                                         generated_datetime, expiry_datetime,
                                         generated_by, max_scans)
                    VALUES (v_tt, fn_generate_token(v_tt, v_date), v_date,
                            TIMESTAMP(v_date, v_start) - INTERVAL 10 MINUTE,
                            TIMESTAMP(v_date, v_start) + INTERVAL 60 MINUTE,
                            2, 1);
                    SET v_qr = LAST_INSERT_ID();

                    /* Mostly punctual; roughly one in seven arrives late. */
                    IF RAND() < 0.14 THEN
                        SET v_offset = 12 + FLOOR(RAND() * 28);   /* 12-39 min: Late */
                    ELSE
                        SET v_offset = FLOOR(RAND() * 11) - 4;    /* -4..6 min: Present */
                    END IF;

                    SET v_scan = TIMESTAMP(v_date, v_start) + INTERVAL v_offset MINUTE;

                    INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date,
                                            scan_datetime, status, scan_ip, device_info, recorded_by)
                    VALUES (v_teacher, v_qr, v_tt, v_date, v_scan, 'Present',
                            CONCAT('192.168.1.', 20 + (v_teacher MOD 200)),
                            'Android 14 / Chrome Mobile', NULL);
                END IF;
            END LOOP;
            CLOSE cur;

            /* Resolve everything with no scan using the production procedure. */
            CALL sp_mark_absentees(v_date, NULL, v_absent, v_excused);
        END IF;
        SET v_date = v_date + INTERVAL 1 DAY;
    END WHILE;
END $$

DELIMITER ;

/* --- build the timetable --------------------------------------------------- */
CALL sp_seed_timetable(1, 2,  1, 12, 1, 9);   /* Winneba: 12 teachers, 9 rooms */
CALL sp_seed_timetable(2, 3, 13,  4, 10, 3);  /* Accra:    4 teachers, 3 rooms */

/* ###########################################################################
   9. LEAVE REQUESTS
   Historical leave has to be inserted before the attendance history, so that
   sp_mark_absentees classifies those days as Excused rather than Absent -
   which is the whole point of proposal problem 4.
   trg_leave_request_bi normally refuses backdated requests, so the backdate
   limit is widened for the load and restored immediately afterwards. Doing it
   through the setting rather than by disabling the trigger means the rule is
   never actually switched off.
   ######################################################################### */
UPDATE system_setting SET setting_value = '3650' WHERE setting_key = 'leave.max_backdate_days';

INSERT INTO leave_request (leave_request_id, teacher_id, leave_type, start_date, end_date, reason, status) VALUES
(1, 3,  'Sick',          '2026-06-08', '2026-06-12', 'Admitted at Winneba Trauma Hospital with malaria', 'Pending'),
(2, 7,  'Study',         '2026-07-06', '2026-07-10', 'Attending MPhil ICT contact session at UEW',       'Pending'),
(3, 11, 'Compassionate', '2026-06-22', '2026-06-24', 'Funeral of immediate family member at Kumasi',     'Pending'),
(4, 5,  'Official Duty', '2026-08-10', '2026-08-12', 'WAEC marking duty at the regional centre',         'Pending'),
(5, 9,  'Casual',        '2026-08-24', '2026-08-26', 'Personal matters requiring travel to Tamale',      'Pending'),
(6, 14, 'Maternity',     '2026-07-13', '2026-08-07', 'Maternity leave as approved by GES',               'Pending');

/* Approve the historical ones through the real procedure, as the headteacher
   would have. Requests 5 and 6 are left Pending to populate the approval
   queue screen. */
CALL sp_action_leave_request(1, 'Approved', 2, 'Medical certificate sighted',        @r1);
CALL sp_action_leave_request(2, 'Approved', 2, 'Approved - study leave, UEW',        @r2);
CALL sp_action_leave_request(3, 'Approved', 2, 'Condolences extended by management', @r3);
CALL sp_action_leave_request(4, 'Approved', 2, 'WAEC duty confirmed',                @r4);

/* ###########################################################################
   10. ATTENDANCE HISTORY
   The full current term up to yesterday. Today is left empty so the live
   board and the check-in screen have something to do during a demonstration.
   ######################################################################### */
CALL sp_seed_history('2026-05-04', CURDATE() - INTERVAL 1 DAY);

/* Restore the real backdating rule. */
UPDATE system_setting SET setting_value = '7' WHERE setting_key = 'leave.max_backdate_days';

/* ###########################################################################
   11. TODAY: a partial day, so the demonstration has live state
   A code is issued for every session that runs today, and the sessions whose
   bell has already rung are checked in - leaving the still-to-come sessions
   waiting, exactly as a real morning would look.
   ######################################################################### */
DELIMITER $$
DROP PROCEDURE IF EXISTS sp_seed_today $$
CREATE PROCEDURE sp_seed_today()
MODIFIES SQL DATA
BEGIN
    DECLARE v_done  TINYINT DEFAULT 0;
    DECLARE v_tt    INT UNSIGNED;
    DECLARE v_teach INT UNSIGNED;
    DECLARE v_start TIME;
    DECLARE v_qr    INT UNSIGNED;
    DECLARE v_code  VARCHAR(64);

    DECLARE cur CURSOR FOR
        SELECT tt.timetable_id, tt.teacher_id, tt.start_time
        FROM timetable tt
        JOIN classroom c ON c.classroom_id = tt.classroom_id
        WHERE tt.is_active = 1
          AND tt.day_of_week = DAYNAME(CURDATE())
          AND fn_is_holiday(c.school_id, CURDATE()) = 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN cur;
    t_loop: LOOP
        FETCH cur INTO v_tt, v_teach, v_start;
        IF v_done = 1 THEN
            LEAVE t_loop;
        END IF;

        /* Issue a code valid from just before the bell until well after it,
           so a live demonstration can still scan an earlier session. */
        INSERT INTO qr_code (timetable_id, code_value, session_date,
                             generated_datetime, expiry_datetime, generated_by, max_scans)
        VALUES (v_tt, fn_generate_token(v_tt, CURDATE()), CURDATE(),
                LEAST(TIMESTAMP(CURDATE(), v_start) - INTERVAL 10 MINUTE, NOW()),
                GREATEST(TIMESTAMP(CURDATE(), v_start) + INTERVAL 60 MINUTE,
                         NOW() + INTERVAL 6 HOUR),
                2, 1);
        SET v_qr = LAST_INSERT_ID();

        /* Check in only the sessions whose bell has already rung, and leave a
           few of those unscanned so the "unstaffed now" alert has content. */
        IF TIMESTAMP(CURDATE(), v_start) < NOW() AND RAND() < 0.8 THEN
            INSERT INTO attendance (teacher_id, qr_code_id, timetable_id, session_date,
                                    scan_datetime, status, scan_ip, device_info)
            VALUES (v_teach, v_qr, v_tt, CURDATE(),
                    TIMESTAMP(CURDATE(), v_start) + INTERVAL FLOOR(RAND() * 9) - 3 MINUTE,
                    'Present', '192.168.1.50', 'Android 14 / Chrome Mobile');
        END IF;
    END LOOP;
    CLOSE cur;
END $$
DELIMITER ;

CALL sp_seed_today();

/* ###########################################################################
   12. REFRESH DERIVED DATA AND OPTIMISER STATISTICS
   Statistics must be recollected after a bulk load, otherwise the optimiser
   plans file 11's queries against the cardinalities of an empty database.
   ######################################################################### */
CALL sp_refresh_attendance_summary('2026-05-04', CURDATE(), @rows);

ANALYZE TABLE attendance PERSISTENT FOR ALL;
ANALYZE TABLE qr_code    PERSISTENT FOR ALL;
ANALYZE TABLE timetable  PERSISTENT FOR ALL;
ANALYZE TABLE teacher    PERSISTENT FOR ALL;
ANALYZE TABLE app_user   PERSISTENT FOR ALL;
ANALYZE TABLE audit_log  PERSISTENT FOR ALL;

/* ###########################################################################
   13. LOAD REPORT
   ######################################################################### */
SELECT 'schools' AS entity, COUNT(*) AS rows_loaded FROM school
UNION ALL SELECT 'roles',            COUNT(*) FROM user_role
UNION ALL SELECT 'users',            COUNT(*) FROM app_user
UNION ALL SELECT 'teachers',         COUNT(*) FROM teacher
UNION ALL SELECT 'classrooms',       COUNT(*) FROM classroom
UNION ALL SELECT 'academic terms',   COUNT(*) FROM academic_term
UNION ALL SELECT 'holidays',         COUNT(*) FROM holiday
UNION ALL SELECT 'timetable slots',  COUNT(*) FROM timetable
UNION ALL SELECT 'qr codes',         COUNT(*) FROM qr_code
UNION ALL SELECT 'attendance rows',  COUNT(*) FROM attendance
UNION ALL SELECT 'leave requests',   COUNT(*) FROM leave_request
UNION ALL SELECT 'audit entries',    COUNT(*) FROM audit_log
UNION ALL SELECT 'security events',  COUNT(*) FROM security_event
UNION ALL SELECT 'summary rows',     COUNT(*) FROM attendance_daily_summary;

SELECT status, COUNT(*) AS rows_recorded,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM attendance GROUP BY status ORDER BY rows_recorded DESC;

SELECT '10 complete - seed data loaded' AS status;
