<?php
require_once __DIR__ . '/db_connect.php';

error_reporting(E_ALL);
ini_set('display_errors', '1');

try {
  $pdo->exec("INSERT IGNORE INTO users (name, username, email, password, profile_pic) VALUES 
  ('Emma Wilson', 'emma_w', 'emma@test.com', '123456', 'https://i.pravatar.cc/400?img=5'),
  ('James Smith', 'james_s', 'james@test.com', '123456', 'https://i.pravatar.cc/400?img=11'),
  ('Sophia Lee', 'sophia_l', 'sophia@test.com', '123456', 'https://i.pravatar.cc/400?img=9')");
  
  $stmt = $pdo->query("SELECT id, name FROM users WHERE email IN ('emma@test.com', 'james@test.com', 'sophia@test.com')");
  $newUsers = $stmt->fetchAll(PDO::FETCH_ASSOC);
  
  foreach ($newUsers as $u) {
      $id = $u['id'];
      $gender = ($u['name'] == 'James Smith') ? 'male' : 'female';
      $cover = 'https://picsum.photos/seed/' . $id . '/600/900';
      
      $sql = "INSERT IGNORE INTO match_profiles (user_id, gender, age, location, bio, is_visible, cover_pic, interests, looking_for, qualities) 
          VALUES ($id, '$gender', 24, 'Kathmandu, Nepal', 'Just looking for good vibes!', 1, '$cover', 'Music,Travel', 'A serious relationship', 'Kind,Funny')";
      $pdo->exec($sql);
      
      // Update fake location so they appear in Nearby tab
      $pdo->exec("UPDATE match_profiles SET lat = 27.7172, lng = 85.3240 WHERE user_id = $id");
  }
  echo "SUCCESSFULLY_SEEDED_USERS";
} catch(Exception $e) {
  echo "SEEDED_ERROR " . $e->getMessage();
}
?>
