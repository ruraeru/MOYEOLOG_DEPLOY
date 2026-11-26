-- 모임 공지 탭 + 투표(feat/group-notice) 운영 마이그레이션 (MySQL 8).
-- 새 백엔드 이미지를 띄우기 전에 한 번 실행한다. 기존 앱이 돌고 있어도 실행해도 된다(ENUM 값을 늘리는 것뿐).
-- 실행 전 백업: backup.sh
--
-- notifications.type 은 MySQL ENUM 이고 Hibernate(ddl-auto=update)는 기존 컬럼 타입을 바꾸지 않는다.
-- 새 알림 종류 GROUP_NOTICE 를 넣지 않으면 공지 알림 저장이 실패한다(리스너가 경고 로그만 남기고 알림은 빠진다).
--
-- 새 테이블 group_notices, group_notice_reads, group_notice_polls, group_notice_poll_options,
-- group_notice_poll_votes 는 새 백엔드가 뜰 때 Hibernate 가 만든다.

ALTER TABLE notifications MODIFY type ENUM('FRIEND_ACCEPTED','FRIEND_REQUEST','GROUP_INVITE','GROUP_KICKED','MEMO_SHARED','SCHEDULE_PARTICIPANT','TOPIC_COMMENT','GROUP_NOTICE') NOT NULL;

-- 확인: SHOW CREATE TABLE notifications;  → `type` enum(... ,'GROUP_NOTICE') NOT NULL
--
-- 되돌리기 (이전 백엔드 이미지로 돌아갈 때). GROUP_NOTICE 알림이 남아 있으면 ENUM 에서 뺄 수 없으므로 먼저 지운다.
-- DELETE FROM notifications WHERE type = 'GROUP_NOTICE';
-- ALTER TABLE notifications MODIFY type ENUM('FRIEND_ACCEPTED','FRIEND_REQUEST','GROUP_INVITE','GROUP_KICKED','MEMO_SHARED','SCHEDULE_PARTICIPANT','TOPIC_COMMENT') NOT NULL;
-- 새 테이블은 이전 백엔드가 쓰지 않으므로 남겨 둬도 된다. 지우려면(자식부터):
-- DROP TABLE group_notice_poll_votes, group_notice_poll_options, group_notice_polls, group_notice_reads, group_notices;
