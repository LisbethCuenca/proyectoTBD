const express = require('express');
const bodyParser = require('body-parser');
const pool = require('./db');
const axios = require('axios');
const PDFDocument = require('pdfkit');
const ExcelJS = require('exceljs'); // Requerir exceljs                                                                                     

const app = express();
const port = 3000;                                                                           

const TMDB_API_KEY = '96854f6207833fe0daa0987536a19775';
const TMDB_BASE_URL = 'https://api.themoviedb.org/3';

app.set('view engine', 'ejs');
app.use(bodyParser.urlencoded({ extended: true }));

let genres = [];

// Función para obtener los géneros de películas desde TMDB
const getGenres = async () => {
  const response = await axios.get(`${TMDB_BASE_URL}/genre/movie/list`, {
    params: {                                 
      api_key: TMDB_API_KEY,
      language: 'es-ES'
    }
  });
  return response.data.genres;
};

// Ruta principal - renderiza el login
app.get('/', (req, res) => {
  res.render('login');
});

// Ruta para el login
app.post('/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const result = await pool.query('SELECT * FROM users WHERE email = $1 AND password = $2', [email, password]);
    if (result.rows.length > 0) {
      res.redirect('/movies');
    } else {
      res.send('Invalid email or password');
    }
  } catch (err) {
    console.error(err.message);
    res.send('An error occurred');
  }
});

// Ruta para el registro de usuarios
app.get('/register', (req, res) => {
  res.render('register');
});

app.post('/register', async (req, res) => {
  const { name, email, password } = req.body;
  try {
    await pool.query('INSERT INTO users (name, email, password) VALUES ($1, $2, $3)', [name, email, password]);
    res.redirect('/movies');
  } catch (err) {
    console.error(err.message);
    res.send('An error occurred');
  }
});

// Ruta para mostrar películas desde TMDB
app.get('/movies', async (req, res) => {
  try {
    if (genres.length === 0) {
      genres = await getGenres();
    }

    const response = await axios.get(`${TMDB_BASE_URL}/movie/popular`, {
      params: {
        api_key: TMDB_API_KEY,
        language: 'es-ES'
      }
    });

    const movies = response.data.results.map(movie => {
      return {
        ...movie,
        genres: movie.genre_ids.map(id => {
          const genre = genres.find(genre => genre.id === id);
          return genre ? genre.name : null;
        }).filter(genre => genre !== null)
      };
    });

    // Aquí agrupa las películas por género
    const moviesByGenre = {};
    movies.forEach(movie => {
      movie.genres.forEach(genre => {
        if (!moviesByGenre[genre]) {
          moviesByGenre[genre] = [];
        }
        moviesByGenre[genre].push(movie);
      });
    });

    res.render('movies', { moviesByGenre }); // Pasar moviesByGenre a la plantilla
  } catch (err) {
    console.error(err.message);
    res.send('An error occurred while fetching movies');
  }
});
                              
// Ruta para buscar películas por título
app.get('/search-movies', async (req, res) => {
  const query = req.query.query; // Obtiene el parámetro de consulta 'query' desde la URL

  try {
    if (genres.length === 0) {
      genres = await getGenres(); // Obtiene los géneros si no se han cargado previamente
    }

    // Realiza la solicitud a la API de TMDB para buscar películas por título
    const response = await axios.get(`${TMDB_BASE_URL}/search/movie`, {
      params: {
        api_key: TMDB_API_KEY,
        query,
        language: 'es-ES'
      }
    });

    // Mapea los resultados para formatear los datos de las películas
    const movies = response.data.results.map(movie => {
      return {
        ...movie,
        genres: movie.genre_ids.map(id => {
          const genre = genres.find(genre => genre.id === id);
          return genre ? genre.name : null;
        }).filter(genre => genre !== null)
      };
    });

    res.json({ results: movies }); // Envía los resultados como JSON
  } catch (err) {
    console.error(err.message);
    res.send('An error occurred while searching for movies');
  }
});

// Rutas para el CRUD de usuarios en el dashboard
app.get('/dashboard', async (req, res) => {
  try {
    const users = await pool.query('SELECT * FROM users');
    res.render('dashboard', { users: users.rows });
  } catch (err) {
    console.error(err.message);
    res.send('Error al cargar el dashboard');
  }
});

app.post('/dashboard/add', async (req, res) => {
  const { name, email, password } = req.body;
  try {
    await pool.query('INSERT INTO users (name, email, password) VALUES ($1, $2, $3)', [name, email, password]);
    res.redirect('/dashboard');
  } catch (err) {
    console.error(err.message);
    res.send('Error al agregar usuario');
  }
});

// Ruta para cargar el formulario de edición de usuario
app.get('/dashboard/edit/:id', async (req, res) => {
  const id = req.params.id;
  try {
    const user = await pool.query('SELECT * FROM users WHERE id = $1', [id]);
    res.render('edit', { user: user.rows[0] });
  } catch (err) {
    console.error(err.message);
    res.send('Error al cargar usuario');
  }
});

app.post('/dashboard/edit/:id', async (req, res) => {
  const id = req.params.id;
  const { name, email, password } = req.body;
  try {
    await pool.query('UPDATE users SET name = $1, email = $2, password = $3 WHERE id = $4', [name, email, password, id]);
    res.redirect('/dashboard');
  } catch (err) {
    console.error(err.message);
    res.send('Error al actualizar usuario');
  }
});

app.get('/dashboard/delete/:id', async (req, res) => {
  const id = req.params.id;
  try {
    await pool.query('DELETE FROM users WHERE id = $1', [id]);
    res.redirect('/dashboard');
  } catch (err) {
    console.error(err.message);
    res.send('Error al eliminar usuario');
  }
});

// Ruta para generar reporte en PDF
app.get('/report/pdf', async (req, res) => {
  try {
    const users = await pool.query('SELECT * FROM users');
    
    if (users.rows.length === 0) {
      throw new Error('No se encontraron usuarios para generar el reporte.');
    }
    
    const doc = new PDFDocument();
    let filename = 'reporte_usuarios.pdf';
    res.setHeader('Content-disposition', 'attachment; filename="' + filename + '"');
    res.setHeader('Content-type', 'application/pdf');
    
    doc.pipe(res);
    doc.fontSize(25).text('Reporte de Usuarios', { align: 'center' });
    doc.moveDown();
    
    users.rows.forEach(user => {
      doc.fontSize(12).text(`ID: ${user.id}`);
      doc.fontSize(12).text(`Nombre: ${user.name}`);
      doc.fontSize(12).text(`Email: ${user.email}`);
      doc.fontSize(12).text(`---------------------------------`);
      doc.moveDown();
    });
    
    doc.end();
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Error al generar el reporte en PDF: ' + err.message);
  }
});
                               

                                
// Ruta para generar reporte en                                                                       
app.get('/report/excel', async (req, res) => {
  try {
    const users = await pool.query('SELECT * FROM users');
    
    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Usuarios');
    
    worksheet.columns = [
      { header: 'ID', key: 'id', width: 10 },
      { header: 'Nombre', key: 'name', width: 30 },
      { header: 'Email', key: 'email', width: 30 },
    ];
    
    users.rows.forEach(user => {
      worksheet.addRow(user);
    });

    let filename = 'reporte_usuarios.xlsx';
    res.setHeader('Content-disposition', 'attachment; filename="' + filename + '"');
    res.setHeader('Content-type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

    await workbook.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error(err.message);
    res.send('Error al generar el reporte en Excel');
  }
});     

// Ruta para generar reporte de películas en PDF
app.get('/report/movies/pdf', async (req, res) => {
  try {
    const response = await axios.get(`${TMDB_BASE_URL}/movie/popular`, {
      params: {
        api_key: TMDB_API_KEY,
        language: 'es-ES'
      }
    });

    const movies = response.data.results;

    if (movies.length === 0) {
      throw new Error('No se encontraron películas para generar el reporte.');
    }

    const doc = new PDFDocument();
    let filename = 'reporte_peliculas_populares.pdf';
    res.setHeader('Content-disposition', 'attachment; filename="' + filename + '"');
    res.setHeader('Content-type', 'application/pdf');

    doc.pipe(res);
    doc.fontSize(25).text('Reporte de Películas Populares', { align: 'center' });
    doc.moveDown();

    movies.forEach(movie => {
      doc.fontSize(12).text(`Título: ${movie.title}`);
      doc.fontSize(12).text(`Descripción: ${movie.overview}`);
      doc.fontSize(12).text(`Fecha de lanzamiento: ${movie.release_date}`);
      doc.fontSize(12).text(`Puntuación: ${movie.vote_average}`);
      doc.fontSize(12).text('---------------------------------');
      doc.moveDown();
    });

    doc.end();
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Error al generar el reporte en PDF: ' + err.message);
  }
});

// Ruta para generar reporte de películas en Excel
app.get('/report/movies/excel', async (req, res) => {
  try {
    const response = await axios.get(`${TMDB_BASE_URL}/movie/popular`, {
      params: {
        api_key: TMDB_API_KEY,
        language: 'es-ES'
      }
    });

    const movies = response.data.results;

    if (movies.length === 0) {
      throw new Error('No se encontraron películas para generar el reporte.');
    }

    const workbook = new ExcelJS.Workbook();
    const worksheet = workbook.addWorksheet('Películas Populares');

    worksheet.columns = [
      { header: 'Título', key: 'title', width: 30 },
      { header: 'Descripción', key: 'overview', width: 50 },
      { header: 'Fecha de lanzamiento', key: 'release_date', width: 15 },
      { header: 'Puntuación', key: 'vote_average', width: 10 }
    ];

    movies.forEach(movie => {
      worksheet.addRow({
        title: movie.title,
        overview: movie.overview,
        release_date: movie.release_date,
        vote_average: movie.vote_average
      });
    });

    let filename = 'reporte_peliculas_populares.xlsx';
    res.setHeader('Content-disposition', 'attachment; filename="' + filename + '"');
    res.setHeader('Content-type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

    await workbook.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error(err.message);
    res.send('Error al generar el reporte en Excel: ' + err.message);
  }
});
                                                                      


app.listen(port, () => {
  console.log(`App running on port ${port}`);
});
         
