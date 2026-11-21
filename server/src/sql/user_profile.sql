-- name: GetOwnProfile :one
SELECT id, name, email, image FROM users WHERE id = sqlc.arg(user_id) LIMIT 1;

-- name: UpdateOwnProfile :one
UPDATE users SET name = sqlc.arg(name), updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE id = sqlc.arg(user_id)
RETURNING id, name, email, image;
