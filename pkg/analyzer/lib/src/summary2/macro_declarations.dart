// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/macros/executor/introspection_impls.dart'
    as macro;
import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart'
    as macro;
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

class ClassDeclarationImpl extends macro.ClassDeclarationImpl {
  late final ClassElement element;

  ClassDeclarationImpl._({
    required super.id,
    required super.identifier,
    required super.library,
    required super.metadata,
    required super.typeParameters,
    required super.interfaces,
    required super.hasAbstract,
    required super.hasBase,
    required super.hasExternal,
    required super.hasFinal,
    required super.hasInterface,
    required super.hasMixin,
    required super.hasSealed,
    required super.mixins,
    required super.superclass,
  });
}

class DeclarationBuilder {
  final DeclarationBuilderFromNode fromNode = DeclarationBuilderFromNode();

  final DeclarationBuilderFromElement fromElement =
      DeclarationBuilderFromElement();

  /// Associate declarations that were previously created for nodes with the
  /// corresponding elements. So, we can access them uniformly via interfaces,
  /// mixins, etc.
  void transferToElements() {
    // TODO(scheglov) Make sure that these are only declarations?
    for (final entry in fromNode._namedTypeMap.entries) {
      final element = entry.key.element;
      if (element != null) {
        final declaration = entry.value;
        fromElement._identifierMap[element] = declaration;
      }
    }
    for (final entry in fromNode._declaredIdentifierMap.entries) {
      final element = entry.key;
      final declaration = entry.value;
      fromElement._identifierMap[element] = declaration;
    }

    for (final entry in fromNode._classMap.entries) {
      final element = entry.key.declaredElement!;
      final declaration = entry.value;
      declaration.element = element;
      fromElement._classMap[element] = declaration;
    }
  }
}

class DeclarationBuilderFromElement {
  final Map<Element, IdentifierImpl> _identifierMap = Map.identity();
  final Map<Element, LibraryImpl> _libraryMap = Map.identity();

  final Map<ClassElement, IntrospectableClassDeclarationImpl> _classMap =
      Map.identity();

  final Map<FieldElement, FieldDeclarationImpl> _fieldMap = Map.identity();

  final Map<TypeParameterElement, macro.TypeParameterDeclarationImpl>
      _typeParameterMap = Map.identity();

  macro.IntrospectableClassDeclarationImpl classElement(ClassElement element) {
    return _classMap[element] ??= _introspectableClassElement(element);
  }

  macro.FieldDeclarationImpl fieldElement(FieldElement element) {
    return _fieldMap[element] ??= _fieldElement(element);
  }

  macro.IdentifierImpl identifier(Element element) {
    return _identifierMap[element] ??= IdentifierImplFromElement(
      id: macro.RemoteInstance.uniqueId,
      name: element.name!,
      element: element,
    );
  }

  macro.LibraryImpl library(Element element) {
    var library = _libraryMap[element.library];
    if (library == null) {
      final version = element.library!.languageVersion.effective;
      library = LibraryImplFromElement(
          id: macro.RemoteInstance.uniqueId,
          languageVersion:
              macro.LanguageVersionImpl(version.major, version.minor),
          // TODO: Provide metadata annotations.
          metadata: const [],
          uri: element.library!.source.uri,
          element: element);
      _libraryMap[element.library!] = library;
    }
    return library;
  }

  macro.TypeParameterDeclarationImpl typeParameter(
    TypeParameterElement element,
  ) {
    return _typeParameterMap[element] ??= _typeParameter(element);
  }

  macro.TypeAnnotationImpl _dartType(DartType type) {
    if (type is InterfaceType) {
      return macro.NamedTypeAnnotationImpl(
        id: macro.RemoteInstance.uniqueId,
        isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
        identifier: identifier(type.element),
        typeArguments: type.typeArguments.map(_dartType).toList(),
      );
    } else if (type is TypeParameterType) {
      return macro.NamedTypeAnnotationImpl(
        id: macro.RemoteInstance.uniqueId,
        isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
        identifier: identifier(type.element),
        typeArguments: const [],
      );
    } else {
      // TODO(scheglov) other types
      throw UnimplementedError('(${type.runtimeType}) $type');
    }
  }

  FieldDeclarationImpl _fieldElement(FieldElement element) {
    assert(!_fieldMap.containsKey(element));
    final enclosingClass = element.enclosingElement2 as ClassElement;
    return FieldDeclarationImpl(
      id: macro.RemoteInstance.uniqueId,
      identifier: identifier(element),
      library: library(element),
      // TODO: Provide metadata annotations.
      metadata: const [],
      hasExternal: element.isExternal,
      hasFinal: element.isFinal,
      hasLate: element.isLate,
      type: _dartType(element.type),
      definingType: identifier(enclosingClass),
      isStatic: element.isStatic,
    );
  }

  IntrospectableClassDeclarationImpl _introspectableClassElement(
      ClassElement element) {
    assert(!_classMap.containsKey(element));
    return IntrospectableClassDeclarationImpl._(
      id: macro.RemoteInstance.uniqueId,
      identifier: identifier(element),
      library: library(element),
      // TODO: Provide metadata annotations.
      metadata: const [],
      typeParameters: element.typeParameters.map(_typeParameter).toList(),
      interfaces: element.interfaces
          .map(_dartType)
          .cast<macro.NamedTypeAnnotationImpl>()
          .toList(),
      hasAbstract: element.isAbstract,
      hasBase: element.isBase,
      hasExternal: false,
      hasFinal: element.isFinal,
      hasInterface: element.isInterface,
      hasMixin: element.isMixinClass,
      hasSealed: element.isSealed,
      mixins: element.mixins
          .map(_dartType)
          .cast<macro.NamedTypeAnnotationImpl>()
          .toList(),
      superclass: element.supertype.mapOrNull(_dartType)
          as macro.NamedTypeAnnotationImpl?,
    )..element = element;
  }

  macro.TypeParameterDeclarationImpl _typeParameter(
    TypeParameterElement element,
  ) {
    return macro.TypeParameterDeclarationImpl(
      id: macro.RemoteInstance.uniqueId,
      identifier: identifier(element),
      library: library(element),
      // TODO: Provide metadata annotations.
      metadata: const [],
      bound: element.bound.mapOrNull(_dartType),
    );
  }
}

class DeclarationBuilderFromNode {
  final Map<ast.NamedType, IdentifierImpl> _namedTypeMap = Map.identity();

  final Map<Element, IdentifierImpl> _declaredIdentifierMap = Map.identity();
  final Map<Element, LibraryImpl> _libraryMap = Map.identity();

  final Map<ast.ClassDeclaration, IntrospectableClassDeclarationImpl>
      _classMap = Map.identity();

  macro.ClassDeclarationImpl classDeclaration(
    ast.ClassDeclaration node,
  ) {
    return _classMap[node] ??= _introspectableClassDeclaration(node);
  }

  macro.LibraryImpl library(Element element) {
    var library = _libraryMap[element.library];
    if (library == null) {
      final version = element.library!.languageVersion.effective;
      library = LibraryImplFromElement(
          id: macro.RemoteInstance.uniqueId,
          languageVersion:
              macro.LanguageVersionImpl(version.major, version.minor),
          // TODO: Provide metadata annotations.
          metadata: const [],
          uri: element.library!.source.uri,
          element: element);
      _libraryMap[element.library!] = library;
    }
    return library;
  }

  macro.IdentifierImpl _declaredIdentifier(Token name, Element element) {
    return _declaredIdentifierMap[element] ??= _DeclaredIdentifierImpl(
      id: macro.RemoteInstance.uniqueId,
      name: name.lexeme,
      element: element,
    );
  }

  macro.FunctionTypeParameterImpl _formalParameter(
    ast.FormalParameter node,
  ) {
    if (node is ast.DefaultFormalParameter) {
      node = node.parameter;
    }

    final macro.TypeAnnotationImpl typeAnnotation;
    if (node is ast.SimpleFormalParameter) {
      typeAnnotation = _typeAnnotation(node.type);
    } else {
      throw UnimplementedError('(${node.runtimeType}) $node');
    }

    return macro.FunctionTypeParameterImpl(
      id: macro.RemoteInstance.uniqueId,
      isNamed: node.isNamed,
      isRequired: node.isRequired,
      name: node.name?.lexeme,
      // TODO: Provide metadata annotations.
      metadata: const [],
      type: typeAnnotation,
    );
  }

  IntrospectableClassDeclarationImpl _introspectableClassDeclaration(
    ast.ClassDeclaration node,
  ) {
    assert(!_classMap.containsKey(node));
    return IntrospectableClassDeclarationImpl._(
      id: macro.RemoteInstance.uniqueId,
      identifier: _declaredIdentifier(node.name, node.declaredElement!),
      library: library(node.declaredElement!),
      // TODO: Provide metadata annotations.
      metadata: const [],
      typeParameters: _typeParameters(node.typeParameters),
      interfaces: _typeAnnotations(node.implementsClause?.interfaces),
      hasAbstract: node.abstractKeyword != null,
      hasBase: node.baseKeyword != null,
      hasExternal: false,
      hasFinal: node.finalKeyword != null,
      hasInterface: node.interfaceKeyword != null,
      hasMixin: node.mixinKeyword != null,
      hasSealed: node.sealedKeyword != null,
      mixins: _typeAnnotations(node.withClause?.mixinTypes),
      superclass: node.extendsClause?.superclass.mapOrNull(
        _typeAnnotation,
      ),
    );
  }

  macro.IdentifierImpl _namedTypeIdentifier(ast.NamedType node) {
    return _namedTypeMap[node] ??= _NamedTypeIdentifierImpl(
      id: macro.RemoteInstance.uniqueId,
      name: node.name2.lexeme,
      node: node,
    );
  }

  T _typeAnnotation<T extends macro.TypeAnnotationImpl>(
      ast.TypeAnnotation? node) {
    if (node == null) {
      return macro.OmittedTypeAnnotationImpl(
        id: macro.RemoteInstance.uniqueId,
      ) as T;
    } else if (node is ast.GenericFunctionType) {
      return macro.FunctionTypeAnnotationImpl(
        id: macro.RemoteInstance.uniqueId,
        isNullable: node.question != null,
        namedParameters: node.parameters.parameters
            .where((e) => e.isNamed)
            .map(_formalParameter)
            .toList(),
        positionalParameters: node.parameters.parameters
            .where((e) => e.isPositional)
            .map(_formalParameter)
            .toList(),
        returnType: _typeAnnotation(node.returnType),
        typeParameters: _typeParameters(node.typeParameters),
      ) as T;
    } else if (node is ast.NamedType) {
      return macro.NamedTypeAnnotationImpl(
        id: macro.RemoteInstance.uniqueId,
        identifier: _namedTypeIdentifier(node),
        isNullable: node.question != null,
        typeArguments: _typeAnnotations(node.typeArguments?.arguments),
      ) as T;
    } else {
      throw UnimplementedError('(${node.runtimeType}) $node');
    }
  }

  List<T> _typeAnnotations<T extends macro.TypeAnnotationImpl>(
    List<ast.TypeAnnotation>? elements,
  ) {
    if (elements != null) {
      return List.generate(
          elements.length, (i) => _typeAnnotation(elements[i]));
    } else {
      return const [];
    }
  }

  macro.TypeParameterDeclarationImpl _typeParameter(
    ast.TypeParameter node,
  ) {
    return macro.TypeParameterDeclarationImpl(
      id: macro.RemoteInstance.uniqueId,
      identifier: _declaredIdentifier(node.name, node.declaredElement!),
      library: library(node.declaredElement!),
      // TODO: Provide metadata annotations.
      metadata: const [],
      bound: node.bound.mapOrNull(_typeAnnotation),
    );
  }

  List<macro.TypeParameterDeclarationImpl> _typeParameters(
    ast.TypeParameterList? typeParameterList,
  ) {
    if (typeParameterList != null) {
      return typeParameterList.typeParameters.map(_typeParameter).toList();
    } else {
      return const [];
    }
  }
}

class FieldDeclarationImpl extends macro.FieldDeclarationImpl {
  FieldDeclarationImpl({
    required super.id,
    required super.identifier,
    required super.library,
    required super.metadata,
    required super.hasExternal,
    required super.hasFinal,
    required super.hasLate,
    required super.type,
    required super.definingType,
    required super.isStatic,
  });
}

abstract class IdentifierImpl extends macro.IdentifierImpl {
  IdentifierImpl({
    required super.id,
    required super.name,
  });

  Element? get element;
}

class IdentifierImplFromElement extends IdentifierImpl {
  @override
  final Element element;

  IdentifierImplFromElement({
    required super.id,
    required super.name,
    required this.element,
  });
}

class IntrospectableClassDeclarationImpl
    extends macro.IntrospectableClassDeclarationImpl {
  late final ClassElement element;

  IntrospectableClassDeclarationImpl._({
    required super.id,
    required super.identifier,
    required super.library,
    required super.metadata,
    required super.typeParameters,
    required super.interfaces,
    required super.hasAbstract,
    required super.hasBase,
    required super.hasFinal,
    required super.hasExternal,
    required super.hasInterface,
    required super.hasMixin,
    required super.hasSealed,
    required super.mixins,
    required super.superclass,
  });
}

abstract class LibraryImpl extends macro.LibraryImpl {
  LibraryImpl({
    required super.id,
    required super.languageVersion,
    required super.metadata,
    required super.uri,
  });

  Element? get element;
}

class LibraryImplFromElement extends LibraryImpl {
  @override
  final Element element;

  LibraryImplFromElement({
    required super.id,
    required super.languageVersion,
    required super.metadata,
    required super.uri,
    required this.element,
  });
}

class _DeclaredIdentifierImpl extends IdentifierImpl {
  @override
  final Element element;

  _DeclaredIdentifierImpl({
    required super.id,
    required super.name,
    required this.element,
  });
}

class _NamedTypeIdentifierImpl extends IdentifierImpl {
  final ast.NamedType node;

  _NamedTypeIdentifierImpl({
    required super.id,
    required super.name,
    required this.node,
  });

  @override
  Element? get element => node.element;
}

extension<T> on T? {
  R? mapOrNull<R>(R Function(T) mapper) {
    final self = this;
    return self != null ? mapper(self) : null;
  }
}
