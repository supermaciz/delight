# Développeur.se Back-End (API Deezer)

<aside>
ℹ️

Langage imposé : [**Elixir](https://elixir-lang.org/)** 
**Toutes les *libraries* publiques sont autorisées, ainsi que tous les outils de développement (IDE, LLM, doc, etc).**

Dans cet exercice tu vas devoir interagir avec la **Web API de Deezer**. **Aucune authentification n’est requise** pour la recherche et le catalogue public.

Documentation complète [ici](https://developers.deezer.com/api) 👈

</aside>

Pour cet exercice nous allons wrapper l’API Deezer. Le but est de publier une API REST ou GraphQL en local permettant de récupérer la liste des albums d’un artiste : 

- Paramètre d’entrée : nom de l’artiste
- En sortie la liste des albums avec leur nom et la date de sortie au format JSON
- Pour chaque nouvel artiste, il faudra enregistrer dans un schéma Postgresql le nom de l’artiste, son Deezer ID ainsi que les albums avec leur nom et date de sortie

### Le rendu

- **Doit être un *repository public* (Github, Gitlab, …)**
- **Doit contenir des instructions nous permettant de tester facilement**

Si tu as des questions sur l’exercice, n’hésites pas à nous envoyer un mail !
