/*
Copyright (c) 2015-2016 Red Hat, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package org.ovirt.sdk.ruby;

import static java.util.stream.Collectors.joining;
import static java.util.stream.Collectors.toCollection;
import static java.util.stream.Collectors.toList;

import java.io.File;
import java.io.IOException;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.List;
import java.util.Optional;
import javax.enterprise.inject.spi.CDI;
import javax.inject.Inject;

import org.ovirt.api.metamodel.concepts.ListType;
import org.ovirt.api.metamodel.concepts.Locator;
import org.ovirt.api.metamodel.concepts.Method;
import org.ovirt.api.metamodel.concepts.Model;
import org.ovirt.api.metamodel.concepts.Name;
import org.ovirt.api.metamodel.concepts.NameParser;
import org.ovirt.api.metamodel.concepts.Parameter;
import org.ovirt.api.metamodel.concepts.PrimitiveType;
import org.ovirt.api.metamodel.concepts.Service;
import org.ovirt.api.metamodel.concepts.StructType;
import org.ovirt.api.metamodel.concepts.Type;
import org.ovirt.api.metamodel.tool.SchemaNames;

/**
 * This class is responsible for generating the classes that represent the services of the model.
 */
public class ServicesGenerator implements RubyGenerator {
    // Well known method names:
    private static final Name ADD = NameParser.parseUsingCase("Add");
    private static final Name GET = NameParser.parseUsingCase("Get");
    private static final Name LIST = NameParser.parseUsingCase("List");
    private static final Name REMOVE = NameParser.parseUsingCase("Remove");
    private static final Name UPDATE = NameParser.parseUsingCase("Update");

    // The directory were the output will be generated:
    protected File out;

    // Reference to the objects used to generate the code:
    @Inject private RubyNames rubyNames;
    @Inject private SchemaNames schemaNames;

    // The buffer used to generate the Ruby code:
    private RubyBuffer buffer;

    /**
     * Set the directory were the output will be generated.
     */
    public void setOut(File newOut) {
        out = newOut;
    }

    public void generate(Model model) {
        // Calculate the file name:
        String fileName = rubyNames.getModulePath() + "/services";
        buffer = CDI.current().select(RubyBuffer.class).get();
        buffer.setFileName(fileName);

        // Generate the source:
        generateSource(model);

        // Write the file:
        try {
            buffer.write(out);
        }
        catch (IOException exception) {
            throw new IllegalStateException("Error writing services file \"" + fileName + "\"", exception);
        }
    }

    private void generateSource(Model model) {
        // Begin module:
        buffer.addComment();
        buffer.addComment("These forward declarations are required in order to avoid circular dependencies.");
        buffer.addComment();
        String moduleName = rubyNames.getModuleName();
        buffer.beginModule(moduleName);
        buffer.addLine();

        // The declarations of the services need to appear in inheritance order, otherwise some symbols won't be
        // defined and that will produce errors. To order them correctly we need first to sort them by name, and
        // then sort again so that bases are before extensions.
        Deque<Service> pending = model.services()
            .sorted()
            .collect(toCollection(ArrayDeque::new));
        Deque<Service> sorted = new ArrayDeque<>(pending.size());
        while (!pending.isEmpty()) {
            Service current = pending.removeFirst();
            Service base = current.getBase();
            if (base == null || sorted.contains(base)) {
                sorted.addLast(current);
            }
            else {
                pending.addLast(current);
            }
        }

        // Generate the forward declarations using the order calculated in the previous step:
        sorted.forEach(x -> {
            generateClassDeclaration(x);
            buffer.addLine("end");
            buffer.addLine();
        });

        // Generate the complete declarations, using the same order:
        sorted.forEach(this::generateService);

        // End module:
        buffer.endModule(moduleName);
        buffer.addLine();

    }

    private void generateService(Service service) {
        // Begin class:
        generateClassDeclaration(service);
        buffer.addLine();

        // Generate the constructor:
        buffer.addComment();
        buffer.addComment("Creates a new implementation of the service.");
        buffer.addComment();
        buffer.addYardTag("param", "connection [Connection] The connection to be used by this service.");
        buffer.addComment();
        buffer.addYardTag("param", "path [String] The relative path of this service, for example `vms/123/disks`.");
        buffer.addComment();
        buffer.addYardTag("api", "private");
        buffer.addComment();
        buffer.addLine("def initialize(connection, path)");
        buffer.addLine(  "@connection = connection");
        buffer.addLine(  "@path = path");
        buffer.addLine("end");
        buffer.addLine();

        // Generate the methods and locators:
        service.methods().sorted().forEach(this::generateMethod);
        service.locators().sorted().forEach(this::generateLocator);
        generatePathLocator(service);

        // Generate other methods that don't correspond to model methods or locators:
        generateToS(service);

        // End class:
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateMethod(Method method) {
        Name name = method.getName();
        if (ADD.equals(name)) {
            generateAddHttpPost(method);
        }
        else if (GET.equals(name) || LIST.equals(name)) {
            generateHttpGet(method);
        }
        else if (REMOVE.equals(name)) {
            generateHttpDelete(method);
        }
        else if (UPDATE.equals(name)) {
            generateHttpPut(method);
        }
        else {
            generateActionHttpPost(method);
        }
    }

    private void generateAddHttpPost(Method method) {
        // Classify the parameters, as they have different treatment. The primary parameter will be the request body and
        // the secondary parameters will be query parameters.
        Parameter primaryParameter = getPrimaryParameter(method);
        List<Parameter> secondaryParameters = getSecondaryParameters(method);

        // Document the method:
        Name methodName = method.getName();
        Type primaryParameterType = primaryParameter.getType();
        Name primaryParameterName = primaryParameter.getName();
        String arg = rubyNames.getMemberStyleName(primaryParameterName);
        String methodDoc = method.getDoc();
        if (methodDoc == null) {
            methodDoc = String.format("Adds a new `%1$s`.", arg);
        }
        buffer.addComment();
        buffer.addComment(methodDoc);
        buffer.addComment();

        // Document the primary parameter:
        String primaryParameterDoc = primaryParameter.getDoc();
        if (primaryParameterDoc == null) {
            primaryParameterDoc = String.format("The `%1$s` to add.", arg);
        }
        buffer.addYardParam(primaryParameter, primaryParameterDoc);
        buffer.addComment();

        // Document the secondary parameters:
        buffer.addYardTag("param", "opts [Hash] Additional options.");
        buffer.addComment();
        secondaryParameters.forEach(parameter -> {
            buffer.addYardOption(parameter);
            buffer.addComment();
        });

        // Document the additional headers:
        buffer.addYardTag("option", "opts [Hash] :headers Additional HTTP headers.");
        buffer.addComment();

        // Document the additional query parameter:
        buffer.addYardTag("option", "opts [Hash] :query Additional URL query parameters.");
        buffer.addComment();

        // Document the return value:
        buffer.addYardReturn(primaryParameter);
        buffer.addComment();

        // Generate the method declaration:
        buffer.addLine("def %1$s(%2$s, opts = {})", rubyNames.getMemberStyleName(methodName), arg);

        // Generate the method body:
        generateConvertLiteral(primaryParameterType, arg);
        buffer.addLine("headers = opts[:headers] || {}");
        buffer.addLine("query = opts[:query] || {}");
        secondaryParameters.forEach(this::generateUrlParameter);
        buffer.addLine("request = HttpRequest.new(method: :POST, url: @path, headers: headers, query: query)");
        generateWriteRequestBody(primaryParameter, arg);
        buffer.addLine("response = @connection.send(request)");
        buffer.addLine("case response.code");
        buffer.addLine("when 200, 201, 202");
        generateReturnResponseBody(primaryParameter);
        buffer.addLine("else");
        buffer.addLine(  "check_fault(response)");
        buffer.addLine("end");

        // End method:
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateActionHttpPost(Method method) {
        // Document the method:
        Name methodName = method.getName();
        String actionName = rubyNames.getMemberStyleName(methodName);
        String methodDoc = method.getDoc();
        if (methodDoc == null) {
            methodDoc = String.format("Executes the `%1$s` method.", actionName);
        }
        buffer.addComment();
        buffer.addComment(methodDoc);
        buffer.addComment();

        // Document the parameters:
        buffer.addYardTag("param", "opts [Hash] Additional options.");
        buffer.addComment();
        method.parameters().sorted().forEach(parameter -> {
            buffer.addYardOption(parameter);
            buffer.addComment();
        });

        // Document the additional headers:
        buffer.addYardTag("option", "opts [Hash] :headers Additional HTTP headers.");
        buffer.addComment();

        // Document the additional query parameter:
        buffer.addYardTag("option", "opts [Hash] :query Additional URL query parameters.");
        buffer.addComment();

        // Generate the method declaration:
        buffer.addLine("def %1$s(opts = {})", actionName);

        // Generate the method body:
        buffer.addLine("headers = opts[:headers] || {}");
        buffer.addLine("query = opts[:query] || {}");
        buffer.addLine("action = Action.new(opts)");
        buffer.addLine("writer = XmlWriter.new(nil, true)");
        buffer.addLine("ActionWriter.write_one(action, writer)");
        buffer.addLine("body = writer.string");
        buffer.addLine("writer.close");
        buffer.addLine("request = HttpRequest.new(");
        buffer.addLine(  "method: :POST,");
        buffer.addLine(  "url: \"#{@path}/%1$s\",", getPath(methodName));
        buffer.addLine(  "body: body,");
        buffer.addLine(  "headers: headers,");
        buffer.addLine(  "query: query");
        buffer.addLine(")");
        buffer.addLine("response = @connection.send(request)");
        buffer.addLine("case response.code");
        buffer.addLine("when 200");
        buffer.addLine(  "action = check_action(response)");
        method.parameters()
            .filter(Parameter::isOut)
            .findFirst()
            .ifPresent(this::generateActionResponse);
        buffer.addLine("else");
        buffer.addLine(  "check_action(response)");
        buffer.addLine("end");

        // End method:
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateActionResponse(Parameter parameter) {
        buffer.addLine("return action.%1$s", rubyNames.getMemberStyleName(parameter.getName()));
    }

    private void generateHttpGet(Method method) {
        // Get input and output parameters:
        List<Parameter> inParameters = method.parameters()
            .filter(Parameter::isIn)
            .sorted()
            .collect(toList());
        List<Parameter> outParameters = method.parameters()
            .filter(Parameter::isOut)
            .sorted()
            .collect(toList());

        // Get the first output parameter:
        Parameter mainParameter = outParameters.stream()
            .findFirst()
            .orElse(null);

        // Document the method:
        buffer.addComment();
        String methodDoc = method.getDoc();
        if (methodDoc == null) {
            methodDoc = "Returns the representation of the object managed by this service.";
        }
        buffer.addComment(methodDoc);
        buffer.addComment();

        // Document the parameters:
        buffer.addYardTag("param", "opts [Hash] Additional options.");
        buffer.addComment();
        inParameters.forEach(parameter -> {
            buffer.addYardOption(parameter);
            buffer.addComment();
        });

        // Document the additional headers:
        buffer.addYardTag("option", "opts [Hash] :headers Additional HTTP headers.");
        buffer.addComment();

        // Document the additional query parameter:
        buffer.addYardTag("option", "opts [Hash] :query Additional URL query parameters.");
        buffer.addComment();

        // Document the return value:
        buffer.addYardReturn(mainParameter);
        buffer.addComment();

        // Generate the method declaration:
        Name methodName = method.getName();
        buffer.addLine("def %1$s(opts = {})", rubyNames.getMemberStyleName(methodName));

        // Generate the method body:
        buffer.addLine("headers = opts[:headers] || {}");
        buffer.addLine("query = opts[:query] || {}");
        inParameters.forEach(this::generateUrlParameter);
        buffer.addLine("request = HttpRequest.new(method: :GET, url: @path, headers: headers, query: query)");
        buffer.addLine("response = @connection.send(request)");
        buffer.addLine("case response.code");
        buffer.addLine("when 200");
        generateReturnResponseBody(mainParameter);
        buffer.addLine("else");
        buffer.addLine(  "check_fault(response)");
        buffer.addLine("end");

        // End method:
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateHttpPut(Method method) {
        // Classify the parameters, as they have different treatment. The primary parameter will be the request body and
        // the secondary parameters will be query parameters.
        Parameter primaryParameter = getPrimaryParameter(method);
        List<Parameter> secondaryParameters = getSecondaryParameters(method);

        // Document the method:
        Type primaryParameterType = primaryParameter.getType();
        Name primaryParameterName = primaryParameter.getName();
        String arg = rubyNames.getMemberStyleName(primaryParameterName);
        String methodDoc = method.getDoc();
        if (methodDoc == null) {
            methodDoc = String.format("Updates the `%1$s`.", arg);
        }
        buffer.addComment();
        buffer.addComment(methodDoc);
        buffer.addComment();

        // Document the primary parameter:
        String primaryParameterDoc = primaryParameter.getDoc();
        if (primaryParameterDoc == null) {
            primaryParameterDoc = String.format("The `%1$s` to update.", arg);
        }
        buffer.addYardParam(primaryParameter, primaryParameterDoc);

        // Document the secondary parameters:
        buffer.addYardTag("param", "opts [Hash] Additional options.");
        buffer.addComment();
        secondaryParameters.forEach(parameter -> {
            buffer.addYardOption(parameter);
            buffer.addComment();
        });

        // Document the additional headers:
        buffer.addYardTag("option", "opts [Hash] :headers Additional HTTP headers.");
        buffer.addComment();

        // Document the additional query parameter:
        buffer.addYardTag("option", "opts [Hash] :query Additional URL query parameters.");
        buffer.addComment();

        // Document the return value:
        buffer.addYardReturn(primaryParameter);
        buffer.addComment();

        // Generate the method declaration:
        Name methodName = method.getName();
        buffer.addLine("def %1$s(%2$s, opts = {})", rubyNames.getMemberStyleName(methodName), arg);

        // Generate the method body:
        generateConvertLiteral(primaryParameterType, arg);
        buffer.addLine("headers = opts[:headers] || {}");
        buffer.addLine("query = opts[:query] || {}");
        secondaryParameters.forEach(this::generateUrlParameter);
        buffer.addLine("request = HttpRequest.new(method: :PUT, url: @path, headers: headers, query: query)");
        generateWriteRequestBody(primaryParameter, arg);
        buffer.addLine("response = @connection.send(request)");
        buffer.addLine("case response.code");
        buffer.addLine("when 200");
        generateReturnResponseBody(primaryParameter);
        buffer.addLine(  "return result");
        buffer.addLine("else");
        buffer.addLine(  "check_fault(response)");
        buffer.addLine("end");

        // End method:
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateConvertLiteral(Type type, String variable) {
        if (type instanceof StructType) {
            buffer.addLine("if %1$s.is_a?(Hash)", variable);
            buffer.addLine(  "%1$s = %2$s.new(%1$s)", variable, rubyNames.getTypeName(type));
            buffer.addLine("end");
        }
        else if (type instanceof ListType) {
            ListType listType = (ListType) type;
            Type elementType = listType.getElementType();
            buffer.addLine("if %1$s.is_a?(Array)", variable);
            buffer.addLine(  "%1$s = List.new(%1$s)", variable);
            buffer.addLine(  "%1$s.each_with_index do |value, index|", variable);
            buffer.addLine(    "if value.is_a?(Hash)");
            buffer.addLine(      "%1$s[index] = %2$s.new(value)", variable, rubyNames.getTypeName(elementType));
            buffer.addLine(    "end");
            buffer.addLine(  "end");
            buffer.addLine("end");
        }
    }

    private void generateWriteRequestBody(Parameter parameter, String variable) {
        Type type = parameter.getType();
        buffer.addLine("begin");
        buffer.addLine(  "writer = XmlWriter.new(nil, true)");
        if (type instanceof StructType) {
            RubyName writer = rubyNames.getWriterName(type);
            buffer.addLine("%1$s.write_one(%2$s, writer)", writer.getClassName(), variable);
        }
        else if (type instanceof ListType) {
            ListType listType = (ListType) type;
            Type elementType = listType.getElementType();
            RubyName writer = rubyNames.getWriterName(elementType);
            buffer.addLine("%1$s.write_many(%2$s, writer)", writer.getClassName(), variable);
        }
        buffer.addLine(  "request.body = writer.string");
        buffer.addLine("ensure");
        buffer.addLine(  "writer.close");
        buffer.addLine("end");
    }

    private void generateReturnResponseBody(Parameter parameter) {
        Type type = parameter.getType();
        buffer.addLine("begin");
        buffer.addLine(  "reader = XmlReader.new(response.body)");
        if (type instanceof StructType) {
            RubyName reader = rubyNames.getReaderName(type);
            buffer.addLine("return %1$s.read_one(reader)", reader.getClassName());
        }
        else if (type instanceof ListType) {
            ListType listType = (ListType) type;
            Type elementType = listType.getElementType();
            RubyName reader = rubyNames.getReaderName(elementType);
            buffer.addLine("return %1$s.read_many(reader)", reader.getClassName());
        }
        buffer.addLine("ensure");
        buffer.addLine(  "reader.close");
        buffer.addLine("end");
    }

    private void generateHttpDelete(Method method) {
        // Get input parameters:
        List<Parameter> inParameters = method.parameters()
            .filter(Parameter::isIn)
            .sorted()
            .collect(toList());

        // Document the method:
        String methodDoc = method.getDoc();
        if (methodDoc == null) {
            methodDoc = "Deletes the object managed by this service.";
        }
        buffer.addComment();
        buffer.addComment(methodDoc);
        buffer.addComment();

        // Document the parameters:
        buffer.addYardTag("param", "opts [Hash] Additional options.");
        buffer.addComment();
        inParameters.forEach(buffer::addYardOption);

        // Document the additional headers:
        buffer.addYardTag("option", "opts [Hash] :headers Additional HTTP headers.");
        buffer.addComment();

        // Document the additional query parameter:
        buffer.addYardTag("option", "opts [Hash] :query Additional URL query parameters.");
        buffer.addComment();

        // Generate the method declaration:
        Name methodName = method.getName();
        buffer.addLine("def %1$s(opts = {})", rubyNames.getMemberStyleName(methodName));

        // Generate method body:
        buffer.addLine("headers = opts[:headers] || {}");
        buffer.addLine("query = opts[:query] || {}");
        inParameters.forEach(this::generateUrlParameter);
        buffer.addLine(  "request = HttpRequest.new(method: :DELETE, url: @path, headers: headers, query: query)");
        buffer.addLine(  "response = @connection.send(request)");
        buffer.addLine(  "unless response.code == 200");
        buffer.addLine(    "check_fault(response)");
        buffer.addLine(  "end");
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateUrlParameter(Parameter parameter) {
        Type type = parameter.getType();
        Name name = parameter.getName();
        String symbol = rubyNames.getMemberStyleName(name);
        String tag = schemaNames.getSchemaTagName(name);
        buffer.addLine("value = opts[:%1$s]", symbol);
        buffer.addLine("unless value.nil?");
        if (type instanceof PrimitiveType) {
            Model model = type.getModel();
            if (type == model.getBooleanType()) {
                buffer.addLine("value = Writer.render_boolean(value)", tag);
            }
            else if (type == model.getIntegerType()) {
                buffer.addLine("value = Writer.render_integer(value)", tag);
            }
            else if (type == model.getDecimalType()) {
                buffer.addLine("value = Writer.render_decimal(value)", tag);
            }
            else if (type == model.getDateType()) {
                buffer.addLine("value = Writer.render_date(value)", tag);
            }
        }
        buffer.addLine(  "query['%1$s'] = value", tag);
        buffer.addLine("end");
    }

    private void generateToS(Service service) {
        RubyName serviceName = rubyNames.getServiceName(service);
        buffer.addComment();
        buffer.addComment("Returns an string representation of this service.");
        buffer.addComment();
        buffer.addYardTag("return", "[String]");
        buffer.addComment();
        buffer.addLine("def to_s");
        buffer.addLine(  "\"#<#{%1$s}:#{@path}>\"", serviceName.getClassName());
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateLocator(Locator locator) {
        Parameter parameter = locator.getParameters().stream().findFirst().orElse(null);
        if (parameter != null) {
            generateLocatorWithParameters(locator);
        }
        else {
            generateLocatorWithoutParameters(locator);
        }
    }

    private void generateLocatorWithParameters(Locator locator) {
        Parameter parameter = locator.parameters().findFirst().get();
        String methodName = rubyNames.getMemberStyleName(locator.getName());
        String argName = rubyNames.getMemberStyleName(parameter.getName());
        RubyName serviceName = rubyNames.getServiceName(locator.getService());
        String doc = locator.getDoc();
        if (doc == null) {
            doc = String.format("Locates the `%1$s` service.", methodName);
        }
        buffer.addComment();
        buffer.addComment(doc);
        buffer.addComment();
        buffer.addYardTag("param", "%1$s [String] The identifier of the `%2$s`.", argName, methodName);
        buffer.addComment();
        buffer.addYardTag("return", "[%1$s] A reference to the `%2$s` service.", serviceName.getClassName(), methodName);
        buffer.addComment();
        buffer.addLine("def %1$s_service(%2$s)", methodName, argName);
        buffer.addLine(  "%1$s.new(@connection, \"#{@path}/#{%2$s}\")", serviceName.getClassName(), argName);
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateLocatorWithoutParameters(Locator locator) {
        String methodName = rubyNames.getMemberStyleName(locator.getName());
        String urlSegment = getPath(locator.getName());
        RubyName serviceName = rubyNames.getServiceName(locator.getService());
        String doc = locator.getDoc();
        if (doc == null) {
            doc = String.format("Locates the `%1$s` service.", methodName);
        }
        buffer.addComment();
        buffer.addComment(doc);
        buffer.addComment();
        buffer.addYardTag("return", "[%1$s] A reference to `%2$s` service.", serviceName.getClassName(), methodName);
        buffer.addComment();
        buffer.addLine("def %1$s_service", methodName);
        buffer.addLine(  "%1$s.new(@connection, \"#{@path}/%2$s\")", serviceName.getClassName(), urlSegment);
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generatePathLocator(Service service) {
        // Begin method:
        buffer.addComment();
        buffer.addComment("Locates the service corresponding to the given path.");
        buffer.addComment();
        buffer.addYardTag("param", "path [String] The path of the service.");
        buffer.addComment();
        buffer.addYardTag("return", "[Service] A reference to the service.");
        buffer.addComment();
        buffer.addLine("def service(path)");
        buffer.addLine(  "if path.nil? || path == ''");
        buffer.addLine(    "return self");
        buffer.addLine(  "end");

        // Generate the code that checks if the path corresponds to any of the locators without parameters:
        service.locators().filter(x -> x.getParameters().isEmpty()).sorted().forEach(locator -> {
            Name name = locator.getName();
            String segment = getPath(name);
            buffer.addLine("if path == '%1$s'", segment);
            buffer.addLine(  "return %1$s_service", rubyNames.getMemberStyleName(name));
            buffer.addLine("end");
            buffer.addLine("if path.start_with?('%1$s/')", segment);
            buffer.addLine(
                "return %1$s_service.service(path[%2$d..-1])",
                rubyNames.getMemberStyleName(name),
                segment.length() + 1
            );
            buffer.addLine("end");
        });

        // If the path doesn't correspond to a locator without parameters, then it will correspond to the locator
        // with parameters, otherwise it is an error:
        Optional<Locator> optional = service.locators().filter(x -> !x.getParameters().isEmpty()).findAny();
        if (optional.isPresent()) {
            Locator locator = optional.get();
            Name name = locator.getName();
            buffer.addLine("index = path.index('/')");
            buffer.addLine("if index.nil?");
            buffer.addLine(  "return %1$s_service(path)", rubyNames.getMemberStyleName(name));
            buffer.addLine("end");
            buffer.addLine(
                "return %1$s_service(path[0..(index - 1)]).service(path[(index +1)..-1])",
                rubyNames.getMemberStyleName(name)
            );
        }
        else {
            buffer.addLine("raise Error.new(\"The path \\\"#{path}\\\" doesn't correspond to any service\")");
        }

        // End method:
        buffer.addLine("end");
        buffer.addLine();
    }

    private void generateClassDeclaration(Service service) {
        RubyName serviceName = rubyNames.getServiceName(service);
        Service base = service.getBase();
        RubyName baseName = base != null? rubyNames.getServiceName(base): rubyNames.getBaseServiceName();
        buffer.addLine("class %1$s < %2$s", serviceName.getClassName(), baseName.getClassName());
    }

    private String getPath(Name name) {
        return name.words().map(String::toLowerCase).collect(joining());
    }

    /**
     * Returns the primary parameter of the given method. The primary parameter is the one that is used in the request
     * body for methods like {@code add} and {@code update}, it is usually the first parameter that is both used for
     * input and output and whose type isn't primitive.
     */
    private Parameter getPrimaryParameter(Method method) {
        return method.parameters()
            .filter(parameter -> parameter.isIn() && parameter.isOut())
            .filter(parameter -> !(parameter.getType() instanceof PrimitiveType))
            .findFirst()
            .orElse(null);
    }

    /**
     * Returns the list of secondary parameters of the given methods. The secondary parameters are those that will be
     * used as query or matrix parameters, they should be used for input only, and their type must be primitive.
     */
    private List<Parameter> getSecondaryParameters(Method method) {
        return method.parameters()
            .filter(parameter -> parameter.isIn() && !parameter.isOut())
            .filter(parameter -> parameter.getType() instanceof PrimitiveType)
            .sorted()
            .collect(toList());
    }
}
