import PathKit
import Stencil

struct TemplateRenderer: Renderer {
    enum RendererType {
        case inPlace
        case usingTemplate
    }
    
    private var defaultContext: Context {
        let environment = Environment(
            loader: FileSystemLoader(paths: [Path(SiteConfiguration.Path.includes.relativeToPath(site.path))]),
            extensions: [SpeltExtension.defaultExtension()],
            templateClass: Template.self
        )
        var contextDict = [String: Any]()
        contextDict["site"] = site.payload
        return Context(dictionary: contextDict, environment: environment)
    }
    
    let site: Site
    let type: RendererType
    
    init(site: Site, type: RendererType = .inPlace) {
        self.site = site
        self.type = type
    }
    
    func render() throws {
        for case let file as FileWithMetadata in site.files {
            switch type {
            case .inPlace:
                try renderInPlace(file)
            case .usingTemplate:
                try renderUsingTemplate(file)
            }
        }
    }
    
    // only renders file contents. ignores template name metadata
    private func renderInPlace(_ file: FileWithMetadata) throws {
        let context = defaultContext
        try context.push(dictionary: file.payload) {
            let template = Template(templateString: file.contents)
            do {
                let rendered = try template.render(context.flatten())
                file.contents = rendered
            }
            catch {
                throw SiteRenderer.RenderError(filePath: file.path, lineNumber: nil, underlyingError: error)
            }
        }
    }
    
    // renders file contents recursively into defined template
    private func renderUsingTemplate(_ file: FileWithMetadata) throws {
        guard let templateName = file.metadata.templateName else {
            // if no template name is defined, rendering stops here
            return
        }
        
        try renderFileWithTemplate(file, templateName: templateName)
    }
    
    private func renderFileWithTemplate(_ file: FileWithMetadata, templateName: String) throws {
        let templatesPath = SiteConfiguration.Path.layouts.relativeToPath(site.path)
        let templatePath = Path(templatesPath) + Path(templateName.stringByAppendingPathExtension("html")!)
        
        let context = defaultContext
        
        do {  
            try context.push(dictionary: file.payload) {
                // FIXME: Is it OK for name to be nil?? I guess it gets pulled from metadata later?
                let template = try Template(templateString: templatePath.read(), environment: context.environment, name: nil)
                let rendered = try template.render(context.flatten())
                let contents = rendered.stringByReplacingFrontMatter("")
                file.contents = contents
                
                if let renderedFileMetadata = try? FrontMatterReader.frontMatterForString(rendered).metadata, let templateName = renderedFileMetadata.templateName {
                    // append file metadata to template file metadata
                    file.metadata = renderedFileMetadata + file.metadata
                    try renderFileWithTemplate(file, templateName: templateName)
                }
            }
        }
        
        catch let error as SiteRenderer.RenderError {
            // method can throw recursively. make sure we only wrap the underlying error once.
            throw error
        }
        catch {
            throw SiteRenderer.RenderError(filePath: templatePath.description, lineNumber: nil, underlyingError: error)
        }
    }
}

extension Metadata {
    var templateName: Swift.String? {
        if let metaString = self["layout"] {
            if case .string(let string) = metaString {
                return string
            }
        }
        return nil
    }
}
