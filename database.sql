CREATE DATABASE login;

CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY NOT NULL, 
  name VARCHAR(200) NOT NULL, 
  email VARCHAR(200) NOT NULL, 
  password VARCHAR(200) NOT NULL, 
  UNIQUE (email)
);


CREATE TABLE movies (
  id SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  overview TEXT,
  release_date DATE,
  genre VARCHAR(255)
);




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
                               


// Ruta para generar reporte en Excel
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

app.listen(port, () => {
  console.log(`App running on port ${port}`);
});
                 
















                 <!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Movies</title>
  <style>
    /* Estilos generales */
    body {
      font-family: Arial, sans-serif;
      background-color: rgb(40, 29, 65);
      color: #fff;
      margin: 0;
      padding: 20px;
    }

    /* Estilos para el contenedor de búsqueda */
    .search-container {
      margin-bottom: 20px;
    }

    input[type="text"] {
      padding: 10px;
      width: 80%;
      font-size: 16px;
    }

    button {
      padding: 10px;
      font-size: 16px;
      cursor: pointer;
    }

    /* Estilos para las tarjetas de películas */
    .movie-carousel-container {
      overflow: hidden;
      position: relative;
      margin-bottom: 20px;
    }

    .movie-carousel {
      display: flex;
      overflow: hidden;
      /* Oculta la barra de deslizamiento */
      scroll-snap-type: x mandatory;
      -webkit-overflow-scrolling: touch;
    }

    .movie {
      margin-right: 10px;
      /* Reducir el margen entre las películas */
      flex: 0 0 calc(25% - 10px);
      /* Ancho fijo para 4 tarjetas por fila */
      position: relative;
      max-width: 200px;
      /* Ajustar el ancho máximo de la tarjeta de película */
      cursor: pointer;
      /* Cambiar el cursor al hacer hover */
    }

    .movie img {
      width: 100%;
      /* Ajusta el ancho al 100% del contenedor */
      max-width: 200px;
      /* Establece un máximo de ancho para evitar que las imágenes sean demasiado grandes */
      height: auto;
      /* Mantiene la proporción de aspecto */
    }

    .movie-info {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      background-color: rgba(0, 0, 0, 0.7);
      padding: 10px;
      text-align: center;
      transition: all 0.3s ease;
      opacity: 0;
    }

    .movie:hover .movie-info {
      opacity: 1;
    }

    .movie-info h3 {
      margin-top: 0;
    }

    .movie-info p {
      margin-bottom: 5px;
    }

    /* Estilos para los controles del carrusel */
    .carousel-controls {
      position: absolute;
      top: 50%;
      transform: translateY(-50%);
      width: 100%;
      display: flex;
      justify-content: space-between;
      z-index: 1;
    }

    .carousel-controls button {
      background-color: rgba(0, 0, 0, 0.5);
      color: #fff;
      border: none;
      padding: 10px;
      cursor: pointer;
      outline: none;
    }

    .carousel-controls button:hover {
      background-color: rgba(0, 0, 0, 0.8);
    }

    .carousel-prev {
      left: 10px;
    }

    .carousel-next {
      right: 10px;
    }

    .cabeza {
      
      height: 50px;
      margin-bottom: 20px;
      display: flex;
    }

    .cabeza {
    display: flex;
    align-items: center;
    justify-content: space-between;
    
    
}

.title a{
    color: white;
    margin: 0;
    
}

.button2 {
    text-decoration: none; /* Elimina la subrayado del link */
    color: white; /* Hace el texto blanco */
    text-decoration: none; 
    
}
   

    .title {
      font-family: 'Impact', sans-serif;
      /* Fuente impactante */
      color: #8b0000;
      /* Color sangre */
      text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.5);
      /* Sombra al texto */
      letter-spacing: 2px;
      /* Espaciado entre letras */
      padding-bottom: 20px;
      /* Espaciado inferior */
      animation: swing 2s infinite alternate;
      /* Animación swing */
    }

    @keyframes swing {
      0% {
        transform: translateX(0);
      }

      100% {
        transform: translateX(30px);
        /* Cambia la distancia de la animación */
      }
    }


    head {}

  </style>
  <div class="cabeza">
    <h1 class="title">PATOFLIX</h1>
    <a href="/dashboard" class="button2">Panel</a>
    <a href="/" class="button2">Cerrar Sesión</a> 
  </div>
</head>

<body>
  <!-- Contenedor de búsqueda -->
  <div class="search-container">
    <input type="text" id="search-input" placeholder="Buscar películas...">
    <button onclick="searchMovies()">Buscar</button>
  </div>

  <!-- Contenedor para mostrar películas -->
  <div id="movies-container" style="display: flex;">
    <!-- Aquí se insertarán las películas buscadas -->
  </div>

  <!-- Carruseles por género -->
  <% Object.keys(moviesByGenre).forEach(genre=> { %>
    <h2>
      <%= genre %>
    </h2>
    <div class="movie-carousel-container">
      <div class="carousel-controls">
        <button class="carousel-prev" onclick="scrollCarousel('prev')">❮</button>
        <button class="carousel-next" onclick="scrollCarousel('next')">❯</button>
      </div>
      <div class="movie-carousel">
        <% moviesByGenre[genre].forEach(movie=> { %>
          <div class="movie"
            onclick="showMovieDetails('<%= movie.title %>', '<%= movie.overview %>', '<%= movie.genres.join(', ') %>')">
            <img src="https://image.tmdb.org/t/p/w500<%= movie.poster_path %>" alt="<%= movie.title %>">
            <div class="movie-info">
              <h3>
                <%= movie.title %>
              </h3>
              <p>
                <%= movie.overview %>
              </p>
              <p>Género: <%= movie.genres.join(', ') %></p>
            </div>
          </div>
        <% }); %>
      </div>
    </div>
  <% }); %>

  <div id="movie-details">
  </div>

  <script>
    async function searchMovies() {
            const query = document.getElementById('search-input').value.trim();
            if (query) {
                try {
                    const response = await fetch(`/search-movies?query=${query}`);
                    if (!response.ok) {
                        throw new Error('Network response was not ok');
                    }
                    const data = await response.json();
                    displayMovies(data.results);
                } catch (error) {
                    console.error('Error fetching movies:', error);
                }
            } else {
                console.error('Search query is empty');
            }
        }

        function displayMovies(movies) {
            const container = document.getElementById('movies-container');
            container.innerHTML = ''; // Clear previous results
            movies.forEach(movie => {
                const movieDiv = document.createElement('div');
                movieDiv.className = 'movie';
                movieDiv.innerHTML = `
                    <img src="https://image.tmdb.org/t/p/w500${movie.poster_path}" alt="${movie.title}">
                    <h2>${movie.title}</h2>
                    <p>${movie.overview}</p>
                    <p>Género: ${movie.genre_ids.join(', ')}</p>
                `;
                container.appendChild(movieDiv);
            });                 
        }                               

    function scrollCarousel(direction) {
      const carousel = document.querySelector('.movie-carousel');
      const scrollAmount = 300; 

      if (direction === 'prev') {
        carousel.scrollBy({
          left: -scrollAmount,
          behavior: 'smooth'
        });
      } else if (direction === 'next') {
        carousel.scrollBy({
          left: scrollAmount,
          behavior: 'smooth'
        });
      }
    }

    function showMovieDetails(title, overview, genres) {
      const detailsContainer = document.getElementById('movie-details');
      detailsContainer.innerHTML = `
                  <h2>${title}</h2>
                  <p>${overview}</p>
                  <p>Género: ${genres}</p>
                  `;
    }
  </script>
</body>
</html>                