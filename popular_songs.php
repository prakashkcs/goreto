<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

echo json_encode([
    'status' => 'success',
    'songs'  => [
        ['title' => 'Nasayo',              'artist' => 'Albatross'],
        ['title' => 'Rara',                'artist' => 'Swoopna Suman'],
        ['title' => 'Swasni',              'artist' => 'Prabesh Kumar Shrestha'],
        ['title' => 'Bhool',               'artist' => 'Sajjan Raj Vaidya'],
        ['title' => 'Rokna Sakdina',       'artist' => 'Sugam Pokhrel'],
        ['title' => 'Sambodhan',           'artist' => 'Sugam Pokhrel'],
        ['title' => 'Timilai Dekhna',      'artist' => 'Sabin Rai'],
        ['title' => 'Sindoor',             'artist' => 'Albatross'],
        ['title' => 'Chhodi Ja',           'artist' => 'Albatross'],
        ['title' => 'Maya',                'artist' => 'Bartika Eam Rai'],
        ['title' => 'Parelima',            'artist' => 'Santosh Lama'],
        ['title' => 'Resham Firiri',       'artist' => 'Traditional'],
        ['title' => 'Kasto Manchhe',       'artist' => '1974 AD'],
        ['title' => 'Yesto Maya',          'artist' => 'Sushant KC'],
        ['title' => 'Aafai Hunthe',        'artist' => 'Nabin K. Bhattarai'],
        ['title' => 'Mann Nai Timilai',    'artist' => 'Nabin K. Bhattarai'],
        ['title' => 'Phool Ko Aakha Ma',   'artist' => 'NB Das'],
        ['title' => 'Taal',                'artist' => 'Neetesh Jung Kunwar'],
        ['title' => 'Nai Nai',             'artist' => 'Samir Shrestha'],
        ['title' => 'Eklai Basa',          'artist' => 'Samir Shrestha'],
    ],
]);
