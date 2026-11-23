-- 배포 전(새 백엔드를 띄우기 전, 기존 앱 중지 후) 실행. 순서: be-auth → be-groups 1~2 → be-memos
-- be-auth

ALTER TABLE users ADD COLUMN email_visible BIT(1) NOT NULL DEFAULT 0;

ALTER TABLE users ADD COLUMN kakao_linked_at DATETIME(6) NULL;

ALTER TABLE users ADD COLUMN tokens_valid_after DATETIME(6) NULL;

ALTER TABLE refresh_tokens ADD COLUMN created_at DATETIME(6) NULL;
ALTER TABLE refresh_tokens ADD COLUMN last_used_at DATETIME(6) NULL;

CREATE TABLE IF NOT EXISTS revoked_access_tokens (
    jti VARCHAR(64) NOT NULL PRIMARY KEY,
    expires_at DATETIME(6) NOT NULL,
    INDEX idx_revoked_access_tokens_expires_at (expires_at)
);

-- be-groups 1~2
-- 1. 같은 (모임, 받는 사람) 의 중복 대기 초대 정리: 가장 오래된 1건만 남긴다
DELETE gi FROM group_invitations gi
JOIN group_invitations keep
  ON keep.group_id = gi.group_id AND keep.invitee_id = gi.invitee_id
 AND keep.status = 'PENDING' AND gi.status = 'PENDING'
 AND (keep.invited_at < gi.invited_at OR (keep.invited_at = gi.invited_at AND keep.id < gi.id));

-- 2. 이미 멤버인 모임의 대기 초대 정리 (코드로 먼저 가입한 경우)
DELETE gi FROM group_invitations gi
JOIN group_members gm ON gm.group_id = gi.group_id AND gm.user_id = gi.invitee_id
WHERE gi.status = 'PENDING';


-- be-memos
-- be-memos 운영 마이그레이션 (MySQL 8). **새 백엔드 이미지를 띄우기 전에** 한 번 실행한다.
-- (먼저 띄우면 Hibernate ddl-auto=update 가 friends.user_low_id/user_high_id 를 NOT NULL 로 0 바이트 채워 추가해서
--  유니크 제약 생성이 실패한다. 그 경우에도 아래 2) 의 UPDATE 부터 다시 돌리면 된다.)
-- 실행 전 백업: backup.sh 또는 mysqldump.

-- 1) memos.version (낙관적 잠금). 엔티티: BIGINT NOT NULL DEFAULT 0. 이미 있으면 건너뛴다.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'memos' AND COLUMN_NAME = 'version');
SET @s := IF(@c = 0, 'ALTER TABLE memos ADD COLUMN version BIGINT NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;
UPDATE memos SET version = 0 WHERE version IS NULL;

-- 2) friends: 두 사람 쌍당 관계 1개. (작은 id, 큰 id) 로 정규화한 컬럼 + 유니크.
--    Java 쪽 정렬(Friend.compareAsBytes)은 BINARY(16) 바이트 비교와 같다 → LEAST/GREATEST 로 채운다.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'friends' AND COLUMN_NAME = 'user_low_id');
SET @s := IF(@c = 0, 'ALTER TABLE friends ADD COLUMN user_low_id BINARY(16) NULL, ADD COLUMN user_high_id BINARY(16) NULL', 'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE friends
SET user_low_id = LEAST(requester_id, receiver_id),
    user_high_id = GREATEST(requester_id, receiver_id);

-- 자기 자신과의 관계(있다면) 삭제
DELETE FROM friends WHERE requester_id = receiver_id;

-- 중복 정리: 같은 쌍에서 ACCEPTED 우선, 그다음 오래된 것, 그다음 id 작은 것 하나만 남긴다.
DELETE f1 FROM friends f1
JOIN friends f2
  ON f1.user_low_id = f2.user_low_id AND f1.user_high_id = f2.user_high_id AND f1.id <> f2.id
WHERE (f2.status = 'ACCEPTED' AND f1.status <> 'ACCEPTED')
   OR (f2.status = f1.status AND (
          COALESCE(f2.created_at, '1970-01-01') < COALESCE(f1.created_at, '1970-01-01')
       OR (COALESCE(f2.created_at, '1970-01-01') = COALESCE(f1.created_at, '1970-01-01') AND f2.id < f1.id)));

ALTER TABLE friends
  MODIFY user_low_id BINARY(16) NOT NULL,
  MODIFY user_high_id BINARY(16) NOT NULL,
  ADD CONSTRAINT uk_friends_pair UNIQUE (user_low_id, user_high_id);

-- 3) memo_shares: 같은 메모를 같은 사람에게 공유한 행은 1개.
DELETE s1 FROM memo_shares s1
JOIN memo_shares s2
  ON s1.memo_id = s2.memo_id AND s1.shared_to_id = s2.shared_to_id AND s1.id <> s2.id
WHERE COALESCE(s2.shared_at, '1970-01-01') < COALESCE(s1.shared_at, '1970-01-01')
   OR (COALESCE(s2.shared_at, '1970-01-01') = COALESCE(s1.shared_at, '1970-01-01') AND s2.id < s1.id);

ALTER TABLE memo_shares ADD CONSTRAINT uk_memo_shares_memo_user UNIQUE (memo_id, shared_to_id);

-- 4) 공유가 이미 끊긴 메모에 남은 즐겨찾기 정리 (작성자·공유받은 사람·모임 멤버가 아닌 사람의 즐겨찾기)
DELETE fav FROM memo_favorites fav
JOIN memos m ON m.id = fav.memo_id
WHERE fav.user_id <> m.author_id
  AND NOT EXISTS (SELECT 1 FROM memo_shares s WHERE s.memo_id = m.id AND s.shared_to_id = fav.user_id)
  AND NOT (m.group_id IS NOT NULL AND EXISTS (SELECT 1 FROM group_members gm WHERE gm.group_id = m.group_id AND gm.user_id = fav.user_id));

-- 5) 친구가 아닌 사람이 남아 있는 개인 일정 참여자 정리 (친구 삭제 시 정리 규칙을 기존 데이터에도 적용)
DELETE sp FROM schedule_participants sp
JOIN schedules s ON s.id = sp.schedule_id
WHERE s.group_id IS NULL
  AND sp.user_id <> s.author_id
  AND NOT EXISTS (SELECT 1 FROM friends f WHERE f.status = 'ACCEPTED'
                  AND f.user_low_id = LEAST(s.author_id, sp.user_id) AND f.user_high_id = GREATEST(s.author_id, sp.user_id));

-- 6) 새 테이블 memo_schedule_mentions(memo_id, schedule_id) 는 ddl-auto 가 만든다. 기존 연결은 '일정 쪽 연결' 로 취급되어
--    메모 수정으로 끊기지 않는다(데이터 손실 없음).

-- be-r2: 이모지 조합 닉네임(보이는 글자 20자)용 컬럼 확장
ALTER TABLE users MODIFY nickname VARCHAR(200) NOT NULL;
