-- Inspección incial de tabla
-- Aquí encontramos 8807 filas donde algunos caracteres son ilegibles
select * from netflix_raw order by title 

-- Eliminamos la tabla para mejorar el tamaño de columnas
DROP TABLE [dbo].[netflix_raw]

-- Cambiar el largo de las columnas para mejor rendimiento   
CREATE TABLE [dbo].[netflix_raw](
    [show_id] [varchar](10) primary key,
    [type] [varchar](10) NULL,
    [title] [nvarchar](200) NULL,
    [director] [varchar](250) NULL,
    [cast] [varchar](1000) NULL,
    [country] [varchar](150) NULL,
    [date_added] [varchar](20) NULL,
    [release_year] [int] NULL,
    [rating] [varchar](10) NULL,
    [duration] [varchar](10) NULL,
    [listed_in] [varchar](100) NULL,
    [description] [varchar](500) NULL
)

-- Comprobaión de que los caracteres sean visibles
select * from netflix_raw where show_id='s5023'

-- Remover duplicados
-- Duplicados por id (no se encontraron duplicados de id)
select show_id, COUNT(*) 
from netflix_raw
group by show_id
having COUNT(*)>1 
-- Duplicados por nombre de pelicula 
-- Duplicados
select title, COUNT(*) as Duplicados
from netflix_raw
group by title
having COUNT(*)>1
-- Ver duplicados (algunos no son duplicados sino versiones pelicula y serie de tv)
select * from netflix_raw
where concat(title, type) in (  -- filtrar aquellos que son del mismo tipo y tienen el mismo nombre
select concat(title, type)
from netflix_raw
group by title, type
having COUNT(*)>1
)
order by title


-- Elimina duplicados, limpia datos nulos y cambia tipos de datos.
with cte as (
select * 
,ROW_NUMBER() over(partition by title , type order by show_id) as rn
from netflix_raw
)
select show_id,type,title,cast(date_added as date) as date_added,release_year
,rating,case when duration is null then rating else duration end as duration,description
into netflix
from cte 

-- Revisar nueva tabla
select * from netflix

-- Generar nuevas tablas de dimensiones

-- Genero
select show_id , trim(value) as genre
into netflix_genre
from netflix_raw
cross apply string_split(listed_in,',')

select * from netflix_genre

-- Director
select show_id , trim(value) as director
into netflix_directors
from netflix_raw
cross apply string_split(director,',')

select * from netflix_directors

-- Paises
select show_id , trim(value) as country
into netflix_country
from netflix_raw
cross apply string_split(country,',')

select * from netflix_country

-- Cast
-- DROP TABLE IF EXISTS netflix_cast;
select show_id , trim(value) as cast
into netflix_cast
from netflix_raw
cross apply string_split(cast,',')

select * from netflix_cast

-- Poblar datos. Asumiendo que un mismo director hace película en el mismo pais
insert into netflix_country
select  show_id,m.country 
from netflix_raw nr
inner join (
select director,country
from  netflix_country nc
inner join netflix_directors nd on nc.show_id=nd.show_id
group by director,country
) m on nr.director=m.director
where nr.country is null

-- Revisar relacion entre director y pais
select director,country
from  netflix_country nc
inner join netflix_directors nd on nc.show_id=nd.show_id
group by director,country

-- LIMPIEZA DE DATOS COMPLETA

/* 1. Para cada director: Contar el número de películas y shows de tv creados por ellos en 
columnas separadas para directores quienes crearon ambos */

select nd.director 
,COUNT(distinct case when n.type='Movie' then n.show_id end) as no_of_movies
,COUNT(distinct case when n.type='TV Show' then n.show_id end) as no_of_tvshow
from netflix n
inner join netflix_directors nd on n.show_id=nd.show_id
group by nd.director
having COUNT(distinct n.type)>1

-- 2. Que pais tiene la mayor cantidad de peliculas de comedia
select  top 1 nc.country , COUNT(distinct ng.show_id ) as no_of_movies
from netflix_genre ng
inner join netflix_country nc on ng.show_id=nc.show_id
inner join netflix n on ng.show_id=nc.show_id
where ng.genre='Comedies' and n.type='Movie'
group by  nc.country
order by no_of_movies desc

-- 3. Para cada año, que director tiene el maximo numero de peliculas
with cte as (
select nd.director,YEAR(date_added) as date_year,count(n.show_id) as no_of_movies
from netflix n
inner join netflix_directors nd on n.show_id=nd.show_id
where type='Movie'
group by nd.director,YEAR(date_added)
)
, cte2 as (
select *
, ROW_NUMBER() over(partition by date_year order by no_of_movies desc, director) as rn
from cte
--order by date_year, no_of_movies desc
)
select * from cte2 where rn=1

-- 4. Cual es la duracion media de cada genero en peliculas (en minutos)

select ng.genre , avg(cast(REPLACE(duration,' min','') AS int)) as avg_duration
from netflix n
inner join netflix_genre ng on n.show_id=ng.show_id
where type='Movie'
group by ng.genre

-- 5. Encontrar la lista de directores que han creato peliculas de terror y comedia. Ambas
select nd.director
, count(distinct case when ng.genre='Comedies' then n.show_id end) as no_of_comedy 
, count(distinct case when ng.genre='Horror Movies' then n.show_id end) as no_of_horror
from netflix n
inner join netflix_genre ng on n.show_id=ng.show_id
inner join netflix_directors nd on n.show_id=nd.show_id
where type='Movie' and ng.genre in ('Comedies','Horror Movies')
group by nd.director
having COUNT(distinct ng.genre)=2;