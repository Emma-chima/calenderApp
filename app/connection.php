<?php
$conn = new mysqli(
  getenv('RDS_HOSTNAME'),
  getenv('RDS_USERNAME'),
  getenv('RDS_PASSWORD'),
  getenv('RDS_DB_NAME'),
  getenv('RDS_PORT')
);
$conn->set_charset("utf8mb4");
