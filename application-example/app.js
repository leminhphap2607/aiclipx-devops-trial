const express = require("express");
const app = express();

const PORT = 5000;

app.get("/", (req, res) => {
  const now = new Date().toLocaleString("en-GB", {
    timeZone: "Asia/Ho_Chi_Minh"
  });

  res.send(`
    <html>
      <head>
        <title>AI Clip X</title>
        <style>
          body {
            margin: 0;
            height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            font-family: Arial, sans-serif;
            background: #0f172a;
            color: white;
          }
          h1 {
            font-size: 48px;
            margin-bottom: 20px;
          }
          p {
            font-size: 20px;
            opacity: 0.8;
          }
        </style>
      </head>
      <body>
        <h1>AI Clip X</h1>
        <p>Current time: ${now}</p>
      </body>
    </html>
  `);
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
