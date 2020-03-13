-- --------------------------------------------------------
# grad_progress
-- --------------------------------------------------------


DROP TABLE IF EXISTS Grad_Progress;
CREATE TABLE Grad_Progress (
  id int(11) AUTO_INCREMENT,
  studentID int(11) NOT NULL,
  semester INT(11) NOT null,
  `subject` varchar(45) NOT NULL,
  semsComplete int(11) NOT NULL,
  semsInProgress int(11) NOT NULL,
  semsReqdGrade int(11) NOT NULL,
  semsClose INT(11) NOT null,
  semsReqdTotal int(11) NOT NULL,
  subjOnTrack VARCHAR(45) NOT NULL,
  overallOnTrack VARCHAR(45) NOT NULL,
  PRIMARY KEY (id),
  KEY `idx01` (studentID),
  KEY `idx02` (`subject`),
  KEY `idx03` (subjOnTrack)
);

truncate table grad_progress;
insert into grad_progress(studentID, semester, `subject`, semsComplete, semsInProgress, semsReqdGrade, semsClose, semsReqdTotal, subjOnTrack, overallOnTrack)
select distinct studentID, -1, `subject`, 0, 0, 0, 0, b.semsReqd, 0, 0
from src_student a
join grad_reqs b
where `subject`<> 'Total' and semester = 8 AND b.gradYear LIKE CONCAT('%', CAST((@currGradYear + -1 * (a.grade - 12)) AS CHAR), '%') ;

DROP TABLE  IF EXISTS grad_sem_req;
CREATE TABLE grad_sem_req AS
(
SELECT b.studentID, c.semester, c.`subject`, c.semsReqd, c.semsClose
FROM
    src_student b 
      JOIN
    grad_reqs c
WHERE 
    CASE
      WHEN b.grade = 8 THEN c.semester = 1 
      WHEN b.grade = 9 THEN c.semester = 1 + @midYear AND c.gradYear LIKE CONCAT('%', CAST((@currGradYear + 3) AS CHAR), '%') 
      WHEN b.grade = 10 THEN c.semester = 3 + @midYear AND c.gradYear LIKE CONCAT('%', CAST((@currGradYear + 2) AS CHAR), '%')   
      WHEN b.grade = 11 THEN c.semester = 5 + @midYear AND c.gradYear LIKE CONCAT('%', CAST((@currGradYear + 1) AS CHAR), '%') 
      WHEN b.grade = 12 THEN c.semester = 7 + @midYear AND c.gradYear LIKE CONCAT('%', CAST((@currGradYear) AS CHAR), '%') 
      ELSE c.semester = 1
    END
);

# Set required semesters for the grade of the student

UPDATE grad_progress a
    INNER JOIN
  grad_sem_req b on a.studentID = b.studentID and  a.`subject` = b.`subject`
SET a.semsReqdGrade = b.semsReqd,
	a.semsClose = b.semsClose,
    a.semester = b.semester;

# All subjects after 8th grade (Not including Algebra I)

DROP TABLE IF EXISTS grad_sems;
CREATE TABLE grad_sems
AS (SELECT studentID, `subject`, 
	FLOOR(SUM(CASE WHEN mark IS null THEN 0 ELSE earnedCredits END)/5) AS semsComp,
	FLOOR(SUM(CASE WHEN mark IS null THEN attemptedCredits ELSE 0 END )/5) AS semsInp
	FROM Transcript
    WHERE (studentGrade > 8 OR (studentGrade = 8 AND semester = 3)) AND UPPER(`subject`) NOT IN ('ALGEBRA I', 'FOREIGN LANGUANGE', 'WORLD HISTORY', 'MATHEMATICS', 'WLD Lang/V&P ARTS/CTE')
    GROUP BY studentID, `subject`);
    
# Insert Algebra I courses

INSERT INTO grad_sems
SELECT studentID, `subject`,
	FLOOR(SUM(CASE WHEN mark IS null THEN 0 ELSE earnedCredits END)/5) AS semsComp,
	FLOOR(SUM(CASE WHEN mark IS null THEN attemptedCredits ELSE 0 END )/5) AS semsInp
	FROM Transcript
	WHERE UPPER(`subject`) IN ('ALGEBRA I', 'FOREIGN LANGUANGE', 'WORLD HISTORY', 'MATHEMATICS', 'WLD Lang/V&P ARTS/CTE')
    GROUP BY studentID, `subject`;
    
#Update sems complete and in progress
CREATE UNIQUE INDEX gs1 ON grad_sems(studentID, `subject`);

UPDATE grad_progress gp
INNER JOIN grad_sems gs
	ON gp.studentID = gs.studentID AND gp.subject = gs.subject
SET gp.semsComplete = gs.semsComp,
	gp.semsInprogress = gs.semsInp;
    
DROP INDEX gs1 ON grad_sems;

#CHANGES#
#table to calculate how much of alg2 semsCompleted we can transfer to alg1

# Keeps track of Algebra 2 semsComp and semsInp
drop table if exists alg2_sems;
create table alg2_sems as
SELECT studentID,
	FLOOR(SUM(CASE WHEN mark IS null THEN 0 ELSE earnedCredits END)/5) AS semsComp,
	FLOOR(SUM(CASE WHEN mark IS null THEN attemptedCredits ELSE 0 END )/5) AS semsInp
	FROM Transcript
	WHERE UPPER(`subject`) IN ('ALGEBRA II')
    GROUP BY studentID, `subject`;


drop table if exists alg2_completed_overflow;
create table alg2_completed_overflow as 
select a2s.studentID,least(needed,semsComp) as transfer
 from (select studentID,greatest(0,semsReqdTotal-semsComplete-semsInProgress)
  as needed from grad_progress where upper(subject) = 'ALGEBRA I') needed_table 
inner join alg2_sems a2s 
on needed_table.studentID=a2s.studentID;

#add transferable completed alg2 sems to alg1 
update grad_progress gp
inner join alg2_completed_overflow a2co
  on gp.studentID  = a2co.studentID
set gp.semsComplete = gp.semsComplete+transfer
where upper(gp.subject) = 'ALGEBRA I';

#subtract transferable alg2 sems from alg2 and place rest in mathematics
update alg2_sems a2s
inner join alg2_completed_overflow a2co on a2s.studentID=a2co.studentID
set a2s.semsComp=a2s.semsComp-transfer;

update grad_progress gp
inner join alg2_sems a2s on gp.studentID=a2s.studentID
set gp.semsComplete=gp.semsComplete+a2s.semsComp
where upper(gp.subject) = 'MATHEMATICS';

#Do the same for In Progress sems
drop table if exists alg2_inprogress_overflow;
create table alg2_inprogress_overflow as 
select a2s.studentID,least(needed,semsInp) as transfer
 from (select studentID,greatest(0,semsReqdTotal-semsComplete-semsInProgress)
  as needed from grad_progress where upper(subject) = 'ALGEBRA I') needed_table 
inner join alg2_sems a2s 
on needed_table.studentID=a2s.studentID;

#add transferable inprogress alg2 sems to alg1 
update grad_progress gp
inner join alg2_inprogress_overflow a2po
  on gp.studentID  = a2po.studentID
set gp.semsInProgress = gp.semsInProgress+transfer
where upper(gp.subject) = 'ALGEBRA I';

#subtract transferable alg2 sems from alg2 and place rest in mathematics
update alg2_sems a2s
inner join alg2_inprogress_overflow a2po on a2s.studentID=a2po.studentID
set a2s.semsInp=a2s.semsInp-transfer;

update grad_progress gp
inner join alg2_sems a2s on gp.studentID=a2s.studentID
set gp.semsInProgress=gp.semsInProgress+a2s.semsInp
where upper(gp.subject) = 'MATHEMATICS';



#ENDOFCHANGES#

# Create table to hold total sems taken
DROP TABLE IF EXISTS grad_total_sems;
CREATE TABLE grad_total_sems
	AS (SELECT studentID, SUM(semsComplete+semsInprogress) AS total
		FROM grad_progress
        GROUP BY studentID);
# Add any semesters above minimum requirements into overflow

DROP TABLE IF EXISTS grad_subj_overflow;
CREATE TABLE grad_subj_overflow
	AS (SELECT 
    studentID, `subject`,
      SUM(CASE
        WHEN semsComplete - semsReqdTotal < 0 THEN 0
        ELSE semsComplete - semsReqdTotal
      END) AS compOverflow,
      SUM(CASE
        WHEN
          (semsInProgress - (CASE
            WHEN semsReqdTotal - semsComplete < 0 THEN 0
            ELSE semsReqdTotal - semsComplete
          END)) < 0
        THEN
          0
        ELSE (semsInProgress - (CASE
          WHEN semsReqdTotal - semsComplete < 0 THEN 0
          ELSE semsReqdTotal - semsComplete
        END))
      END) AS inpOverflow
  FROM
    grad_progress  
  WHERE
    `subject` <> 'Electives' AND (semsComplete + semsInProgress) > semsReqdTotal
  GROUP BY studentID, `subject`);
  
/* Removing sum (possibly unneeded) and using greatest instead of nested case for better readability
DROP TABLE IF EXISTS grad_subj_overflow2;
CREATE TABLE grad_subj_overflow2
	AS (SELECT 
    studentID, `subject`,
      greatest(0,semsComplete - semsReqdTotal) AS compOverflow,
      CASE
        WHEN
          (semsInProgress - greatest(semsReqdTotal-semsComplete,0)) < 0
        THEN
          0
        ELSE (semsInProgress - greatest(semsReqdTotal-semsComplete,0))
      END AS inpOverflow
  FROM
    grad_progress  
  WHERE
    `subject` <> 'Electives' AND (semsComplete + semsInProgress) > semsReqdTotal
  GROUP BY studentID, `subject`);
*/

UPDATE
  grad_progress gp
    INNER JOIN
  (SELECT 
    studentID, `subject`,
      SUM(compOverflow) AS compOverflow,
      SUM(inpOverflow) AS inpOverflow
  FROM
    grad_subj_overflow  
  GROUP BY studentID) overf ON gp.studentID = overf.studentID
SET 
  gp.semsComplete = gp.semsComplete + overf.compOverflow,
  gp.semsInProgress = gp.semsInProgress + overf.inpOverflow
WHERE 
  gp.`subject` = 'Electives';

# Subtract the overflow from the original subjects so there will be no double count
UPDATE grad_progress gp
INNER JOIN grad_subj_overflow gso
	ON gp.studentID = gso.studentID AND gp.subject = gso.subject
SET 
gp.semsComplete = gp.semsComplete - gso.compOverflow,
gp.semsInProgress = gp.semsInProgress - gso.inpOverflow;

/*
#Total overflow
DROP TABLE IF EXISTS grad_total_overflow;
CREATE TABLE grad_total_overflow
	AS (SELECT studentID, SUM(compOverflow) AS compOverflow, SUM(inpOverflow) AS inpOverflow
		FROM grad_subj_overflow
        GROUP BY studentID);
*/

# Courses with two subjects. Format : primary|secondary
DROP TABLE IF EXISTS dual_courses;
CREATE TABLE dual_courses AS 
(
SELECT studentID, subject,  SUBSTRING(subject, 1, INSTR(subject, '|')-1) AS primarySubj, SUBSTRING(subject, INSTR(subject, '|')+1, LENGTH(subject)) AS secondarySubj, 
	   FLOOR(SUM(CASE WHEN mark > 0 THEN earnedCredits ELSE 0 END)/5) AS semsComplete, FLOOR(SUM(CASE WHEN mark IS null THEN attemptedCredits ELSE 0 END)/5) AS semsInProgress,
       0 AS primaryComplete, 0 AS primaryInProgress, 0 AS secondaryComplete, 0 AS secondaryInProgress, 0 AS overflowComplete, 0 AS overflowInProgress
FROM Transcript
WHERE subject LIKE '%|%'
GROUP BY studentID, subject
);

# Count how many credits are used for the primary subject
UPDATE dual_courses dc
INNER JOIN grad_progress gp
	ON dc.studentID = gp.studentID AND dc.primarySubj = gp.subject
SET 
	dc.primaryComplete = CASE WHEN (gp.semsComplete + gp.semsInProgress + dc.semsComplete) >= gp.semsReqdTotal
							  THEN gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress) -- dc.semsComplete - (gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress))
                              ELSE dc.semsComplete
						 END,
	dc.primaryInProgress = CASE WHEN (gp.semsComplete + gp.semsInProgress + dc.semsComplete) >= gp.semsReqdTotal
								THEN 0
                                WHEN (gp.semsComplete + gp.semsInProgress + dc.semsComplete + dc.semsInProgress) >= gp.semsReqdTotal
                                THEN gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress + dc.semsComplete)-- dc.semsInProgress - (gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress + dc.semsComplete))
                                ELSE dc.semsInProgress
						   END
WHERE gp.semsReqdTotal > (gp.semsComplete + gp.semsInProgress);

#Count how many credits are used for the secondary subject

UPDATE dual_courses dc
INNER JOIN grad_progress gp
	ON  dc.studentID = gp.studentID AND dc.secondarySubj = gp.subject
SET
	dc.secondaryComplete = CASE WHEN (gp.semsComplete + gp.semsInProgress + (dc.semsComplete - dc.primaryComplete)) >= gp.semsReqdTotal
								THEN gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress) -- (dc.semsComplete - dc.primaryComplete) - (gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress))
                                ELSE dc.semsComplete - dc.primaryComplete
						   END,
	dc.secondaryInProgress = CASE WHEN (gp.semsComplete + gp.semsInProgress + (dc.semsComplete - dc.primaryComplete)) >= gp.semsReqdTotal
								  THEN 0
                                  WHEN (gp.semsComplete + gp.semsInPRogress + (dc.semsComplete - dc.primaryComplete) + (dc.semsInProgress - dc.primaryInProgress)) >= gp.semsReqdTotal
                                  THEN gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress) -- (dc.semsInProgress - dc.primaryInProgress) - (gp.semsReqdTotal - (gp.semsComplete + gp.semsInProgress + (dc.semsComplete - dc.primaryComplete)))
                                  ELSE dc.semsInProgress - dc.primaryInProgress
							 END
WHERE gp.semsReqdTotal > (gp.semsComplete + gp.semsInProgress);


# The rest in dual_courses are overflow
UPDATE dual_courses
SET
overflowComplete = semsComplete - (primaryComplete + secondaryComplete),
overflowInProgress = semsInProgress - (primaryInProgress + secondaryInProgress);

#Update primarySubj from dual_courses in grad_progress
UPDATE grad_progress gp
INNER JOIN dual_courses dc
	ON gp.studentID = dc.studentID AND gp.subject = dc.primarySubj
SET
	gp.semsComplete = gp.semsComplete + dc.primaryComplete,
    gp.semsInProgress = gp.semsInProgress + dc.primaryInProgress;
    
#Update secondarySubj from dual_courses in grad_progress
UPDATE grad_progress gp
INNER JOIN dual_courses dc
	ON gp.studentID = dc.studentID AND gp.subject = dc.secondarySubj
SET
	gp.semsComplete = gp.semsComplete + dc.secondaryComplete,
    gp.semsInProgress = gp.semsInProgress + dc.secondaryInProgress;
    
#Update electives using dual_courses
UPDATE grad_progress gp
INNER JOIN (SELECT studentID, SUM(overflowComplete) AS overflowComplete, SUM(overflowInProgress) AS overflowInProgress
 			FROM dual_courses
            GROUP BY studentID) dc
	ON gp.studentID = dc.studentID AND gp.subject = 'Electives'
SET
	gp.semsComplete = gp.semsComplete + dc.overflowComplete,
    gp.semsInProgress = gp.semsInProgress + dc.overflowInProgress;

        
# Set the subject on track flag
UPDATE grad_progress
SET 
  subjOnTrack = CASE WHEN semsComplete + semsInProgress >= semsReqdGrade THEN 2
					 WHEN semsComplete + semsInProgress >= semsClose THEN 1
                     ELSE 0
				END;
  
# Table for worst status received across subjects
DROP TABLE IF EXISTS min_subj_status;
CREATE TABLE min_subj_status AS
(
SELECT studentID, MIN(subjOnTrack) AS minStatus
FROM grad_progress
GROUP BY studentID 
); 
  
# Table for sum of sems across subjects
DROP TABLE IF EXISTS total_grad_sems;
CREATE TABLE total_grad_sems AS
(
SELECT studentID, MAX(semester) AS semester, SUM(semsComplete) AS semsComplete, SUM(semsInProgress) AS semsInProgress
FROM grad_progress
GROUP BY studentID
);

#Table for if student is on track for total grad sems
DROP TABLE IF EXISTS total_grad_sems_status;
CREATE TABLE total_grad_sems_status AS
(
SELECT tgs.studentID, tgs.semester, 
		CASE WHEN (tgs.semsComplete + tgs.semsInProgress) >= gr.semsReqd THEN 2
			 WHEN (tgs.semsComplete + tgs.semsInProgress) >= gr.semsClose THEN 1
             ELSE 0
		END AS semStatus
FROM total_grad_sems tgs
INNER JOIN grad_reqs gr
	ON tgs.semester = gr.semester AND gr.subject IN ('Total', 'T') AND gr.gradYear LIKE CONCAT('%',CAST((@currGradYear + (-1 * (CEIL(tgs.semester/2) - 4))) AS CHAR),'%')
);

# Final status for each student
CREATE INDEX mss1 ON min_subj_status(studentID);
CREATE INDEX tgss1 ON total_grad_sems_status(studentID);

DROP TABLE IF EXISTS final_grad_status;
CREATE TABLE final_grad_status AS
(
SELECT mss.studentID, tgss.semester, mss.minStatus, tgss.semStatus, LEAST(mss.minStatus, tgss.semStatus) AS finalStatus
FROM min_subj_status mss
INNER JOIN total_grad_sems_status tgss
	ON mss.studentID = tgss.studentID
);

DROP INDEX mss1 ON min_subj_status;
DROP INDEX tgss1 ON total_grad_sems_status;

UPDATE grad_progress gp
SET 
subjOnTrack = CASE WHEN subjOnTrack = 2 THEN 'on track'
				   WHEN subjOnTrack = 1 THEN 'close'
                   ELSE 'off track'
			  END;
              
UPDATE grad_progress gp
INNER JOIN final_grad_status fgs
	ON gp.studentID = fgs.studentID
SET
gp.overallOnTrack = fgs.finalStatus;



UPDATE student_status ss
INNER JOIN final_grad_status fgs
	ON ss.studentID = fgs.studentID
SET
ss.gradStatus = CASE WHEN fgs.finalStatus = 2 THEN 'on track'
					 WHEN fgs.finalStatus = 1 THEN 'close'
                     ELSE 'off track'
				END;
                
ALTER TABLE Grad_Progress
DROP COLUMN semester, DROP COLUMN overallOnTrack, CHANGE COLUMN semsClose semsReqdClose INT(11), CHANGE COLUMN subject hsSubject VARCHAR(45), CHANGE COLUMN subjOnTrack subjStatus VARCHAR(45);