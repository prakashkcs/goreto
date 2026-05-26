const https = require('https');
https.get('https://coinzop.com/ekloadmin/api/v1/profile_v18.php?user_id=9', (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => console.log(data));
}).on('error', err => console.error(err));
