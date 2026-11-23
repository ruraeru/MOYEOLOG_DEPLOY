-- 배포 후(새 백엔드가 뜬 뒤) 실행
UPDATE group_invitations SET pending_flag = b'1' WHERE status = 'PENDING' AND pending_flag IS NULL;
SELECT COUNT(*) AS data_url_topics FROM group_topics WHERE image_url LIKE 'data:%';
