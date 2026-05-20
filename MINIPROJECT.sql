-- ============================================================================
-- DỰ ÁN: MINI SOCIAL NETWORK (DATABASE CENTRIC)
-- ============================================================================

DROP DATABASE IF EXISTS mini_social_network;
CREATE DATABASE mini_social_network CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mini_social_network;

-- ============================================================================
-- 1. TẠO SCHEMA VÀ RÀNG BUỘC (KHÔNG DÙNG ON DELETE CASCADE)
-- ============================================================================

CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE posts (
    post_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

CREATE TABLE comments (
    comment_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    -- ĐÃ BỎ ON DELETE CASCADE
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES posts(post_id) 
) ENGINE=InnoDB;

CREATE TABLE likes (
    like_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    -- ĐÃ BỎ ON DELETE CASCADE
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES posts(post_id),
    CONSTRAINT unique_user_post_like UNIQUE (user_id, post_id)
) ENGINE=InnoDB;

CREATE TABLE friends (
    friendship_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_friends_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_friends_friend FOREIGN KEY (friend_id) REFERENCES users(user_id),
    UNIQUE KEY unique_friendship_network ((LEAST(user_id, friend_id)), (GREATEST(user_id, friend_id)))
) ENGINE=InnoDB;

CREATE TABLE post_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT,
    author_id INT,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    old_content TEXT
) ENGINE=InnoDB;

-- ============================================================================
-- 2. TRIGGER XỬ LÝ LỖI & THỐNG KÊ
-- ============================================================================

DELIMITER //

-- Trigger xử lý lỗi: Không cho phép kết bạn với chính mình
CREATE TRIGGER before_friend_insert
BEFORE INSERT ON friends
FOR EACH ROW
BEGIN
    IF NEW.user_id = NEW.friend_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi nghiệp vụ: Không thể tự kết bạn với chính mình!';
    END IF;
END //

CREATE TRIGGER after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count + 1 WHERE post_id = NEW.post_id;
END //

CREATE TRIGGER after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count - 1 WHERE post_id = OLD.post_id;
END //

CREATE TRIGGER after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count + 1 WHERE post_id = NEW.post_id;
END //

CREATE TRIGGER after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count - 1 WHERE post_id = OLD.post_id;
END //

CREATE TRIGGER after_post_delete_log
AFTER DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, author_id, old_content)
    VALUES (OLD.post_id, OLD.user_id, OLD.content);
END //

DELIMITER ;

-- ============================================================================
-- 3. STORED PROCEDURES & TRANSACTIONS (XỬ LÝ LỖI CHUẨN)
-- ============================================================================

DELIMITER //

-- Thủ tục đăng ký (Có xử lý lỗi trùng lặp)
CREATE PROCEDURE sp_register_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100)
)
BEGIN
    -- Xử lý lỗi nếu username hoặc email đã tồn tại (Lỗi 1062 trong MySQL)
    DECLARE EXIT HANDLER FOR 1062 
    BEGIN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Username hoặc Email đã được sử dụng!';
    END;

    INSERT INTO users (username, password, email) 
    VALUES (p_username, p_password, p_email);
END //

-- Xóa bài viết an toàn bằng Transaction
CREATE PROCEDURE sp_delete_post(
    IN p_post_id INT,
    IN p_user_id INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi hệ thống khi xóa bài viết, đã rollback!';
    END;

    START TRANSACTION;
        -- Kiểm tra quyền sở hữu
        IF EXISTS (SELECT 1 FROM posts WHERE post_id = p_post_id AND user_id = p_user_id) THEN
            -- Xóa thủ công dữ liệu con do không dùng CASCADE
            DELETE FROM likes WHERE post_id = p_post_id;
            DELETE FROM comments WHERE post_id = p_post_id;
            -- Cuối cùng xóa bài viết
            DELETE FROM posts WHERE post_id = p_post_id AND user_id = p_user_id;
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi: Không tìm thấy bài viết hoặc bạn không có quyền xóa!';
        END IF;
    COMMIT;
END //

-- Xóa User an toàn bằng Transaction (Làm sạch toàn bộ dependency)
CREATE PROCEDURE sp_delete_user_account(IN p_user_id INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lỗi hệ thống khi xóa người dùng, đã rollback toàn bộ!';
    END;

    START TRANSACTION;
        -- 1. Xóa bạn bè
        DELETE FROM friends WHERE user_id = p_user_id OR friend_id = p_user_id;

        -- 2. Xóa likes và comments user này đã tương tác dạo
        DELETE FROM likes WHERE user_id = p_user_id;
        DELETE FROM comments WHERE user_id = p_user_id;

        -- 3. Quan trọng: Xóa likes và comments TRÊN các bài viết CỦA user này
        DELETE FROM likes WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);
        DELETE FROM comments WHERE post_id IN (SELECT post_id FROM posts WHERE user_id = p_user_id);

        -- 4. Xóa bài viết của user
        DELETE FROM posts WHERE user_id = p_user_id;

        -- 5. Cuối cùng mới xóa user
        DELETE FROM users WHERE user_id = p_user_id;
    COMMIT;
END //

DELIMITER ;

-- ============================================================================
-- 4. VIEW & INDEX
-- ============================================================================

CREATE FULLTEXT INDEX idx_posts_content ON posts(content);

CREATE OR REPLACE VIEW view_user_activity_report AS
SELECT 
    u.user_id,
    u.username,
    COUNT(DISTINCT p.post_id) AS total_posts,
    COALESCE(SUM(p.like_count), 0) AS total_likes_received,
    COALESCE(SUM(p.comment_count), 0) AS total_comments_received
FROM users u
LEFT JOIN posts p ON u.user_id = p.user_id
GROUP BY u.user_id, u.username;

-- ============================================================================
-- 5. DỮ LIỆU MẪU (TEST DATA) 
-- ============================================================================

-- Thêm Users
CALL sp_register_user('nguyen_van_a', 'hash1', 'a@gmail.com');
CALL sp_register_user('le_thi_b', 'hash2', 'b@gmail.com');
CALL sp_register_user('tran_van_c', 'hash3', 'c@gmail.com');

-- Đăng bài
INSERT INTO posts (user_id, content) VALUES (1, 'Hello mọi người, đây là bài viết đầu tiên của tôi!');
INSERT INTO posts (user_id, content) VALUES (2, 'Hôm nay trời đẹp quá, đi cafe không anh em?');
INSERT INTO posts (user_id, content) VALUES (1, 'Bài viết số 2 để test chức năng xóa post nhé.');

-- Kết bạn
INSERT INTO friends (user_id, friend_id, status) VALUES (1, 2, 'accepted');
INSERT INTO friends (user_id, friend_id, status) VALUES (2, 3, 'pending');

-- Tương tác (Likes & Comments)
INSERT INTO likes (user_id, post_id) VALUES (2, 1);
INSERT INTO likes (user_id, post_id) VALUES (3, 1);
INSERT INTO comments (post_id, user_id, content) VALUES (1, 2, 'Chào bạn mới nhé!');
INSERT INTO comments (post_id, user_id, content) VALUES (2, 1, 'Lên kèo luôn bạn ơi.');

-- ============================================================================
-- 6. TEST CASES GỌI THỬ (CHẠY ĐỂ KIỂM CHỨNG)
-- ============================================================================
-- Thử xóa bài viết an toàn (Bài số 1 của User 1) -> Sẽ tự xóa 2 likes, 1 comment liên quan
CALL sp_delete_post(1, 1);

-- Thử xóa User an toàn (User 2) -> Xóa bạn bè, bài viết số 2, comment của User 2
CALL sp_delete_user_account(2);

-- Kiểm tra kết quả
SELECT * FROM users;
SELECT * FROM posts;
SELECT * FROM post_logs;
