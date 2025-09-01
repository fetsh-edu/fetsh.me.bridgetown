---
# Feel free to add content and custom Front Matter to this file.

layout: default
---
<ul>
  <% collections.posts.reject { |post| post.data.hidden }.each do |post| %>
    <li>
      <a href="<%= post.relative_url %>"><%= post.data.title %></a>
    </li>
  <% end %>
</ul>
