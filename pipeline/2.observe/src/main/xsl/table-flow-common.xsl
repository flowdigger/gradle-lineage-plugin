<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:c="urn:table-flow-common"
                exclude-result-prefixes="xs c"
                expand-text="yes">

    <xsl:param name="input-uri" as="xs:string?" select="''"/>
    <xsl:param name="schema-name" as="xs:string?" select="''"/>
    <xsl:param name="ext" as="xs:string?">xir</xsl:param>

    <xsl:function name="c:as-uri" as="xs:string">
        <xsl:param name="path" as="xs:string"/>
        <xsl:sequence select="if (matches($path, '^[A-Za-z][A-Za-z0-9+.-]*:'))
                              then $path
                              else string(resolve-uri($path, 'file:///'))"/>
    </xsl:function>

    <xsl:function name="c:collection-uri" as="xs:string">
        <xsl:param name="context" as="node()"/>
        <xsl:param name="dir" as="xs:string?"/>

        <xsl:variable name="provided-uri" select="if (normalize-space($dir)) then normalize-space($dir) else ''" as="xs:string"/>

        <xsl:choose>
            <xsl:when test="contains($provided-uri, '?select=')">
                <xsl:sequence select="$provided-uri"/>
            </xsl:when>
            <xsl:when test="$provided-uri ne ''">
                <xsl:variable name="base-uri" select="c:as-uri($provided-uri)" as="xs:string"/>
                <xsl:variable name="dir-uri" select="if (ends-with($base-uri, '/')) then $base-uri else $base-uri || '/'" as="xs:string"/>
                <xsl:sequence select="$dir-uri || '?select=*.' || $ext || ';recurse=yes;on-error=ignore'"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="base-dir-uri" select="replace(string(base-uri($context)), '[^/]+$', '')" as="xs:string"/>
                <xsl:variable name="dir-uri" select="if (ends-with($base-dir-uri, '/')) then $base-dir-uri else $base-dir-uri || '/'" as="xs:string"/>
                <xsl:sequence select="$dir-uri || '?select=*.' || $ext || ';recurse=no;on-error=ignore'"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <xsl:function name="c:procedure-containers" as="element()*">
        <xsl:param name="doc" as="document-node()"/>
        <xsl:sequence select="if (exists($doc/lineage/procedure))
                              then $doc/lineage/procedure
                              else $doc/lineage"/>
    </xsl:function>

    <xsl:function name="c:view-containers" as="element()*">
        <xsl:param name="doc" as="document-node()"/>
        <xsl:sequence select="$doc/lineage/view"/>
    </xsl:function>

    <xsl:function name="c:procedure-name" as="xs:string">
        <xsl:param name="container" as="element()"/>
        <xsl:variable name="explicit-name" select="if ($container/self::procedure) then normalize-space(string($container/@name)) else ''" as="xs:string"/>
        <xsl:variable name="uri" select="string((document-uri(root($container)), base-uri($container))[1])" as="xs:string"/>
        <xsl:sequence select="if ($explicit-name ne '')
                              then $explicit-name
                              else replace(tokenize($uri, '/')[last()], '\.xml$', '')"/>
    </xsl:function>

    <xsl:function name="c:view-name" as="xs:string">
        <xsl:param name="view" as="element()"/>
        <xsl:sequence select="normalize-space(string($view/@name))"/>
    </xsl:function>

    <xsl:function name="c:view-sources" as="xs:string*">
        <xsl:param name="view" as="element()"/>
        <xsl:sequence select="$view/from/@name ! normalize-space(.)[not(. = ('','dual'))]"/>
    </xsl:function>

    <xsl:function name="c:reads" as="xs:string*">
        <xsl:param name="container" as="element()"/>
        <xsl:sequence select="$container/*[self::insert or self::update or self::merge or self::delete]/from/@name ! normalize-space(.)[not(. = ('','dual'))]"/>
    </xsl:function>

    <xsl:function name="c:writes" as="xs:string*">
        <xsl:param name="container" as="element()"/>
        <xsl:sequence select="$container/*[self::insert or self::update or self::merge or self::delete]/to/@name ! normalize-space(.)[not(. = ('','dual'))]"/>
    </xsl:function>

    <xsl:function name="c:resolve-schema" as="xs:string">
        <xsl:param name="schema" as="xs:string?"/>
        <xsl:param name="first-uri" as="xs:string"/>
        <xsl:sequence select="if (normalize-space($schema)) then normalize-space($schema)
                              else if (matches($first-uri, '/oracle/[^/]+/')) then replace($first-uri, '^.*?/oracle/([^/]+)/.*$', '$1')
                              else 'unknown'"/>
    </xsl:function>

    <xsl:function name="c:strip-query" as="xs:string">
        <xsl:param name="uri" as="xs:string?"/>
        <xsl:sequence select="replace(normalize-space($uri), '\?.*$', '')"/>
    </xsl:function>

    <xsl:function name="c:parent-dir-uri" as="xs:string">
        <xsl:param name="uri" as="xs:string?"/>
        <xsl:variable name="base" select="replace(c:strip-query($uri), '/+$', '')" as="xs:string"/>
        <xsl:variable name="parent" select="replace($base, '/[^/]*$', '')" as="xs:string"/>
        <xsl:sequence select="if (ends-with($parent, '/')) then $parent else $parent || '/'"/>
    </xsl:function>

    <xsl:function name="c:schema-matches-doc" as="xs:boolean">
        <xsl:param name="doc" as="document-node()"/>
        <xsl:param name="schema" as="xs:string?"/>
        <xsl:variable name="schema-lc" select="lower-case(normalize-space($schema))" as="xs:string"/>
        <xsl:variable name="uri" select="lower-case(string((document-uri($doc), base-uri($doc))[1]))" as="xs:string"/>
        <xsl:variable name="prefix" select="$schema-lc || '.'" as="xs:string"/>
        <xsl:variable name="table-refs" as="xs:string*"
                      select="($doc//to/@name, $doc//from/@name) ! lower-case(normalize-space(.))"/>
        <xsl:variable name="procedure-refs" as="xs:string*"
                      select="$doc//procedure/@name ! lower-case(normalize-space(.))"/>
        <xsl:variable name="call-schemas" as="xs:string*"
                      select="$doc//call/@schema ! lower-case(normalize-space(.))"/>
        <xsl:sequence select="
            if ($schema-lc = '') then true()
            else contains('/' || $uri || '/', '/' || $schema-lc || '/')
                 or (some $p in $procedure-refs satisfies starts-with($p, $prefix))
                 or (some $t in $table-refs satisfies starts-with($t, $prefix))
                 or (some $c in $call-schemas satisfies $c = $schema-lc)"/>
    </xsl:function>

    <xsl:function name="c:safe-collection" as="document-node()*">
        <xsl:param name="uri" as="xs:string"/>
        <xsl:try>
            <xsl:sequence select="collection($uri)"/>
            <xsl:catch errors="*">
                <xsl:sequence select="()"/>
            </xsl:catch>
        </xsl:try>
    </xsl:function>

    <xsl:function name="c:docs-for-schema" as="document-node()*">
        <xsl:param name="context" as="node()"/>
        <xsl:param name="input-uri" as="xs:string?"/>
        <xsl:param name="schema" as="xs:string?"/>

        <xsl:variable name="primary-uri" select="c:collection-uri($context, $input-uri)" as="xs:string"/>
        <xsl:variable name="primary-docs" select="c:safe-collection($primary-uri)" as="document-node()*"/>
        <xsl:variable name="fallback-uri"
                      select="c:parent-dir-uri($input-uri) || '?select=*.' || $ext || ';recurse=yes;on-error=ignore'"
                      as="xs:string"/>
        <xsl:variable name="resolved-docs"
                      select="if (exists($primary-docs)) then $primary-docs else c:safe-collection($fallback-uri)"
                      as="document-node()*"/>
        <xsl:sequence select="$resolved-docs[c:schema-matches-doc(., $schema)]"/>
    </xsl:function>

</xsl:stylesheet>
