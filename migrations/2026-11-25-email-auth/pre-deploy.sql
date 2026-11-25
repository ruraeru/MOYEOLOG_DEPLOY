-- 이메일 가입 + 카카오 연동(feat/email-auth) 운영 마이그레이션 (MySQL 8).
-- 새 백엔드 이미지를 띄우기 전에 한 번 실행한다. 기존 앱이 돌고 있어도 실행해도 된다(NOT NULL 을 푸는 것뿐).
-- 실행 전 백업: backup.sh
--
-- Hibernate(ddl-auto=update)는 기존 컬럼의 NULL 허용 여부를 바꾸지 않는다. 이메일로만 가입한 계정은 kakao_id 가
-- NULL 이므로 직접 푼다. 운영 정의(2026-11-25 SHOW CREATE TABLE users): `kakao_id` varchar(255) NOT NULL,
-- UNIQUE KEY `UKk4ycaj27putgcujmehwbsrmmc` (`kakao_id`). 유니크 키는 그대로 둔다(MySQL 유니크 인덱스는 NULL 을 여러 개 허용).
--
-- 새 컬럼(users.password_hash, email_verified_at, failed_login_count, login_locked_until)과
-- 새 테이블 email_verifications 는 새 백엔드가 뜰 때 Hibernate 가 만든다.

ALTER TABLE users MODIFY kakao_id VARCHAR(255) NULL;

-- 확인: SHOW CREATE TABLE users;  → `kakao_id` varchar(255) DEFAULT NULL
--
-- 되돌리기 (이전 백엔드 이미지로 돌아갈 때). 이메일 가입 계정(kakao_id IS NULL)이 있으면 NOT NULL 로 되돌릴 수 없다.
-- 먼저 SELECT COUNT(*) FROM users WHERE kakao_id IS NULL; 로 확인하고, 있으면 그 계정을 어떻게 할지 정한 뒤 실행한다.
-- ALTER TABLE users MODIFY kakao_id VARCHAR(255) NOT NULL;
-- 새 컬럼·테이블은 이전 백엔드가 쓰지 않으므로 남겨 둬도 된다. 지우려면:
-- ALTER TABLE users DROP COLUMN password_hash, DROP COLUMN email_verified_at,
--                   DROP COLUMN failed_login_count, DROP COLUMN login_locked_until;
-- DROP TABLE email_verifications;
