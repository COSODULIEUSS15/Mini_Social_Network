-- ============================================================================
-- DỰ ÁN: MINI SOCIAL NETWORK (DATABASE CENTRIC)
-- THIẾT KẾ & TỐI ƯU HÓA TRÊN HỆ QUẢN TRỊ CSDL MYSQL 8.0+
-- TẤT CẢ TRONG MỘT FILE (ALL-IN-ONE SCRIPT)
-- ============================================================================

-- 1. KHỞI TẠO CƠ SỞ DỮ LIỆU
DROP DATABASE IF EXISTS mini_social_network;
CREATE DATABASE mini_social_network CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mini_social_network;

-- ============================================================================
-- 2. TẠO CẤU TRÚC BẢNG (SCHEMA) VÀ RÀNG BUỘC (CONSTRAINTS)
-- ============================================================================

-- Bảng users: Lưu thông tin người dùng
CREATE TABLE users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL, -- Mật khẩu giả định đã mã hóa hash
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Bảng posts: Lưu bài viết của người dùng
CREATE TABLE posts (
    post_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    -- Không dùng CASCADE ở đây để kiểm soát việc xóa User qua Transaction bài bản
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users(user_id)
) ENGINE=InnoDB;

-- Bảng comments: Bình luận của bài viết
CREATE TABLE comments (
    comment_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    -- Sử dụng ON DELETE CASCADE theo chiến lược: Xóa Post thì xóa luôn Comment
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Bảng likes: Lượt thích bài viết
CREATE TABLE likes (
    like_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    -- Sử dụng ON DELETE CASCADE theo chiến lược: Xóa Post thì xóa luôn Like
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    -- F03: Chặn người dùng like trùng lặp trên cùng một bài viết
    CONSTRAINT unique_user_post_like UNIQUE (user_id, post_id)
) ENGINE=InnoDB;

-- Bảng friends: Quản lý mối quan hệ bạn bè
CREATE TABLE friends (
    friendship_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_friends_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_friends_friend FOREIGN KEY (friend_id) REFERENCES users(user_id),
    -- F04: Chặn việc tự kết bạn với chính mình
    CONSTRAINT chk_not_self_friend CHECK (user_id != friend_id),
    -- F04: Chặn trạng thái không hợp lệ
    CONSTRAINT chk_friendship_status CHECK (status IN ('pending', 'accepted')),
    -- F04: Functional Unique Index (MySQL 8+) để chặn kết bạn đảo chiều (A->B và B->A)
    UNIQUE KEY unique_friendship_network ((LEAST(user_id, friend_id)), (GREATEST(user_id, friend_id)))
) ENGINE=InnoDB;

-- Bảng post_logs: Ghi log phục vụ Audit khi xóa bài viết (Mục 4.1 SRS)
CREATE TABLE post_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    post_id INT,
    author_id INT,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    old_content TEXT
) ENGINE=InnoDB;


-- ============================================================================
-- 3. CÀI ĐẶT TRIGGER (TỰ ĐỘNG HÓA THỐNG KÊ DỮ LIỆU)
-- ============================================================================

DELIMITER //

-- Trigger 3.1: Tăng like_count khi có lượt Like mới
CREATE TRIGGER after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET like_count = like_count + 1 
    WHERE post_id = NEW.post_id;
END //

-- Trigger 3.2: Giảm like_count khi người dùng Hủy Like
CREATE TRIGGER after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET like_count = like_count - 1 
    WHERE post_id = OLD.post_id;
END //

-- Trigger 3.3: Tăng comment_count khi có bình luận mới
CREATE TRIGGER after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET comment_count = comment_count + 1 
    WHERE post_id = NEW.post_id;
END //

-- Trigger 3.4: Giảm comment_count khi bình luận bị xóa
CREATE TRIGGER after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts 
    SET comment_count = comment_count - 1 
    WHERE post_id = OLD.post_id;
END //

-- Trigger 3.5: Ghi log khi có bài viết bị xóa (Phục vụ Audit)
CREATE TRIGGER after_post_delete_log
AFTER DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id, author_id, old_content)
    VALUES (OLD.post_id, OLD.user_id, OLD.content);
END //

DELIMITER ;


-- ============================================================================
-- 4. TẠO INDEX VÀ VIEW (TỐI ƯU HÓA TRUY VẤN)
-- ============================================================================

-- F07: Tạo Full-Text Search Index trên cột content của bảng posts để tìm kiếm nhanh
CREATE FULLTEXT INDEX idx_posts_content ON posts(content);

-- F06: VIEW xem trang cá nhân của người dùng công khai
CREATE OR REPLACE VIEW view_user_profile AS
SELECT 
    user_id, 
    username, 
    email, 
    created_at 
FROM users;

-- F08: VIEW Báo cáo hoạt động chi tiết của từng User
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
-- 5. CÀI ĐẶT STORED PROCEDURES & TRANSACTIONS (LOGIC NGHIỆP VỤ)
-- ============================================================================

DELIMITER //

-- F01: Đăng ký thành viên mới
CREATE PROCEDURE sp_register_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100)
)
BEGIN
    INSERT INTO users (username, password, email) 
    VALUES (p_username, p_password, p_email);
END //

-- F02: Đăng bài viết mới
CREATE PROCEDURE sp_create_post(
    IN p_user_id INT,
    IN p_content TEXT
)
BEGIN
    INSERT INTO posts (user_id, content) 
    VALUES (p_user_id, p_content);
END //

-- F04: Gửi lời mời kết bạn 
CREATE PROCEDURE sp_send_friend_request(
    IN p_user_id INT,
    IN p_friend_id INT
)
BEGIN
    INSERT INTO friends (user_id, friend_id, status) 
    VALUES (p_user_id, p_friend_id, 'pending');
END //

-- F05: Chấp nhận lời mời kết bạn (Cập nhật trạng thái)
CREATE PROCEDURE sp_accept_friend_request(
    IN p_user_id INT,
    IN p_friend_id INT
)
BEGIN
    UPDATE friends 
    SET status = 'accepted'
    WHERE (user_id = p_user_id AND friend_id = p_friend_id)
       OR (user_id = p_friend_id AND friend_id = p_user_id);
END //

-- F09: Gợi ý kết bạn sử dụng CTE (Bạn của bạn - Mutual Friends nhưng chưa kết bạn)
CREATE PROCEDURE sp_suggest_friends(IN p_user_id INT)
BEGIN
    WITH user_friends AS (
        -- Lấy danh sách bạn bè hiện tại của user này (cả 2 chiều)
        SELECT IF(user_id = p_user_id, friend_id, user_id) AS friend_id
        FROM friends
        WHERE (user_id = p_user_id OR friend_id = p_user_id) AND status = 'accepted'
    ),
    friends_of_friends AS (
        -- Tìm bạn của bạn bè
        SELECT IF(f.user_id = uf.friend_id, f.friend_id, f.user_id) AS fof_id
        FROM friends f
        JOIN user_friends uf ON f.user_id = uf.friend_id OR f.friend_id = uf.friend_id
        WHERE f.status = 'accepted'
    )
    SELECT DISTINCT u.user_id, u.username, u.email
    FROM friends_of_friends fof
    JOIN users u ON fof.fof_id = u.user_id
    WHERE fof.fof_id != p_user_id -- Không gợi ý chính mình
      AND fof.fof_id NOT IN (SELECT friend_id FROM user_friends) -- Không gợi ý người đã là bạn
    ORDER BY u.username;
END //

-- F10: Quản lý xóa bài viết chính chủ (Sử dụng Transaction thủ công)
CREATE PROCEDURE sp_delete_post(
    IN p_post_id INT,
    IN p_user_id INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
    END;

    START TRANSACTION;
        -- Kiểm tra đúng chính chủ bài viết thì mới thực hiện xóa
        -- Khi xóa post, likes và comments sẽ tự động bay màu nhờ ON DELETE CASCADE
        DELETE FROM posts 
        WHERE post_id = p_post_id AND user_id = p_user_id;
    COMMIT;
END //

-- F11: Xóa tài khoản người dùng an toàn (Transaction - Nguyên lý ACID: All or Nothing)
CREATE PROCEDURE sp_delete_user_account(IN p_user_id INT)
BEGIN
    -- Nếu có bất kỳ lỗi SQL nào xảy ra, lập tức ROLLBACK toàn bộ dữ liệu về ban đầu
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
    END;

    START TRANSACTION;
        -- Bước 1: Xóa toàn bộ mối quan hệ bạn bè liên quan đến user này
        DELETE FROM friends WHERE user_id = p_user_id OR friend_id = p_user_id;

        -- Bước 2: Xóa toàn bộ lượt thích (likes) mà user này đã đi bấm cho người khác
        DELETE FROM likes WHERE user_id = p_user_id;

        -- Bước 3: Xóa toàn bộ bình luận (comments) mà user này đã đi viết dạo
        DELETE FROM comments WHERE user_id = p_user_id;

        -- Bước 4: Xóa toàn bộ các bài viết (posts) do user này đăng
        -- (Khi xóa posts ở đây, Trigger ghi log và CASCADE cho likes/comments của bài đó sẽ tự chạy)
        DELETE FROM posts WHERE user_id = p_user_id;

        -- Bước 5: Cuối cùng, khi các bảng phụ đã sạch bóng, ta mới xóa tài khoản trong bảng gốc
        DELETE FROM users WHERE user_id = p_user_id;
    COMMIT;
END //

DELIMITER ;


-- ============================================================================
-- 6. CHÈN DỮ LIỆU MẪU (SEED DATA) ĐỂ KIỂM THỬ HỆ THỐNG
-- ============================================================================

-- Thêm 4 người dùng mẫu
CALL sp_register_user('dat_nguyen', 'hash_pass_1', 'dat@ptit.edu.vn');
CALL sp_register_user('hoang_an', 'hash_pass_2', 'an@gmail.com');
CALL sp_register_user('minh_khoi', 'hash_pass_3', 'khoi@yahoo.com');
CALL sp_register_user('thu_thao', 'hash_pass_4', 'thao@outlook.com');

-- Đăng một số bài viết (Đạt đăng 2 bài, An đăng 1 bài)
CALL sp_create_post(1, 'Hôm nay học phần Trigger với Transaction trong MySQL phê thực sự!');
CALL sp_create_post(1, 'Có ai tham gia CLB CodeKing thế hệ 2 không nhỉ?');
CALL sp_create_post(2, 'Thời tiết Sài Gòn dạo này nóng quá trời ơi...');

-- Tạo mạng lưới quan hệ bạn bè
-- Đạt gửi lời mời kết bạn tới An, An chấp nhận lời mời
CALL sp_send_friend_request(1, 2);
CALL sp_accept_friend_request(1, 2);

-- An kết bạn với Khôi và đã chấp nhận
CALL sp_send_friend_request(2, 3);
CALL sp_accept_friend_request(2, 3);

-- Khôi gửi lời mời kết bạn tới Thảo (Đang ở trạng thái chờ - pending)
CALL sp_send_friend_request(3, 4);

-- Tương tác: Bấm Thích và Bình luận bài viết
-- An và Khôi thích bài viết số 1 của Đạt
INSERT INTO likes (user_id, post_id) VALUES (2, 1);
INSERT INTO likes (user_id, post_id) VALUES (3, 1);

-- Khôi thích bài viết số 2 của Đạt
INSERT INTO likes (user_id, post_id) VALUES (3, 2);

-- Thêm bình luận vào bài viết số 1 của Đạt
INSERT INTO comments (post_id, user_id, content) VALUES (1, 2, 'Chuẩn luôn ông ơi, học cuốn cực!');
INSERT INTO comments (post_id, user_id, content) VALUES (1, 3, 'Xin tài liệu tự học với bạn hiền.');


-- ============================================================================
-- 7. KỊCH BẢN KIỂM THỬ (TEST CASES SANITY CHECK)
-- ============================================================================

-- Kiểm tra 7.1: Xem danh sách bài viết hiện tại kèm số đếm tự động (Xem Trigger chạy đúng không)
SELECT post_id, content, like_count, comment_count FROM posts;

-- Kiểm tra 7.2: Thử nghiệm Full-Text Search (Tìm bài viết có chứa chữ 'MySQL')
SELECT * FROM posts WHERE MATCH(content) AGAINST('MySQL' IN NATURAL LANGUAGE MODE);

-- Kiểm tra 7.3: Xem báo cáo hoạt động tổng quan qua View công khai
SELECT * FROM view_user_activity_report;

-- Kiểm tra 7.4: Chạy thử gợi ý kết bạn (Đạt là bạn của An, An là bạn của Khôi -> Gợi ý Khôi cho Đạt)
CALL sp_suggest_friends(1);

-- Kiểm tra 7.5: Thử xóa tài khoản qua TRANSACTION an toàn (Xóa tài khoản Hoàng An - ID: 2)
-- Toàn bộ likes, comments, bài viết và bạn bè của Hoàng An sẽ bay màu đồng bộ, an toàn
CALL sp_delete_user_account(2);

-- Kiểm tra lại sau khi xóa tài khoản:
SELECT * FROM users;
SELECT * FROM posts;
SELECT * FROM post_logs; -- Kiểm tra xem log xóa bài viết của An đã được ghi nhận chưa