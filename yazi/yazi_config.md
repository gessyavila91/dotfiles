
# 🗂️ Configuración de `yazi`

## 📄 **Introducción**
Este archivo contiene instrucciones detalladas para instalar y configurar plugins en `yazi`. Todos los pasos están diseñados para que puedas personalizar tu experiencia al máximo.

## 🛠️ **Configuración de Plugins**

### 📍 **Ubicación del archivo de configuración**
El archivo principal para configurar `yazi` se encuentra en:
```bash
~/.config/yazi/config.lua
```

### 🌟 **Pasos para instalar plugins**
1. **Crea una carpeta para los plugins:**
   ```bash
   mkdir -p ~/.config/yazi/plugins
   ```

2. **Descarga el plugin deseado desde GitHub:**
   Por ejemplo, para un plugin de vista previa de archivos:
   ```bash
   curl -o ~/.config/yazi/plugins/file_preview.lua https://raw.githubusercontent.com/username/repo/branch/file_preview.lua
   ```

3. **Enlaza el plugin en tu archivo de configuración:**
   Abre el archivo `~/.config/yazi/config.lua` y añade:
   ```lua
   require("plugins.file_preview")
   ```

4. **Reinicia `yazi` para aplicar los cambios:**
   ```bash
   yazi
   ```

---

## 🧩 **Lista de Plugins Recomendados**

### 🔍 **1. Vista previa de archivos**
- **Descripción**: Permite previsualizar archivos como imágenes, texto o PDFs.
- **Instalación**:
  ```lua
  require("plugins.file_preview")
  ```

---

### 🔎 **2. Búsqueda fuzzy**
- **Descripción**: Integra un buscador tipo `fzf` para encontrar archivos rápidamente.
- **Instalación**:
  ```lua
  require("plugins.fuzzy_finder")
  ```

---

### 🎨 **3. Resaltado de sintaxis**
- **Descripción**: Resalta la sintaxis en archivos de texto y código.
- **Instalación**:
  ```lua
  require("plugins.syntax_highlight")
  ```

---

### 📌 **4. Gestión de marcadores**
- **Descripción**: Agrega marcadores para directorios o archivos y accede a ellos rápidamente.
- **Instalación**:
  ```lua
  require("plugins.bookmarks")
  ```

---

### 🌲 **5. Explorador en forma de árbol**
- **Descripción**: Divide la pantalla para mostrar múltiples carpetas al mismo tiempo.
- **Instalación**:
  ```lua
  require("plugins.split_pane")
  ```

---

### 🛡️ **6. Integración con Git**
- **Descripción**: Muestra el estado de archivos y carpetas según el repositorio Git.
- **Instalación**:
  ```lua
  require("plugins.git_integration")
  ```

---

### 🎹 **7. Atajos personalizados**
- **Descripción**: Define atajos de teclado personalizados en `yazi`.
- **Instalación**:
  ```lua
  require("plugins.custom_keybindings")
  ```

---

### 🔍 **8. Extensiones de búsqueda avanzada**
- **Descripción**: Agrega soporte para búsquedas dentro de los archivos (por contenido).
- **Instalación**:
  ```lua
  require("plugins.advanced_search")
  ```

---

## ✅ **Revisión Final**
- Una vez configurados los plugins, verifica que `yazi`
