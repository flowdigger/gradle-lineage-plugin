<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:f="urn:table-procedure-index"
                exclude-result-prefixes="xs f"
                expand-text="yes">

    <!--~
        Output: XML
        Indents output for readability.
    -->
    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-skip"/>

    <!--~
        Param: input-uri
        Description: Optional directory or URI containing extracted lineage XML files for one schema.
    -->
    <xsl:param name="input-uri" as="xs:string?" select="''"/>
    <!--~
        Param: schema-name
        Description: Optional name of the database schema.
    -->
    <xsl:param name="schema-name" as="xs:string?" select="''"/>

    <!--~
        Function: f:as-uri
        Description: Converts a file path to a URI, or returns the path if already a URI.
        Parameters:
            - path: The file path or URI.
        Returns: The URI as a string.
    -->
    <xsl:function name="f:as-uri" as="xs:string">
        <xsl:param name="path" as="xs:string"/>
        <xsl:sequence select="if (matches($path, '^[A-Za-z][A-Za-z0-9+.-]*:'))
                              then $path
                              else string(resolve-uri($path, 'file:///'))"/>
    </xsl:function>

    <!--~
        Function: f:collection-uri
        Description: Builds a URI for a directory of XML files, used for collection().
        Parameters:
            - context: The context node.
            - dir: The directory path or URI.
        Returns: The collection URI as a string.
    -->
    <xsl:function name="f:collection-uri" as="xs:string">
        <xsl:param name="context" as="node()"/>
        <xsl:param name="dir" as="xs:string?"/>

        <!-- If a URI with query parameters is provided, use it as-is -->
        <xsl:variable name="provided-uri" select="if (normalize-space($dir)) then normalize-space($dir) else ''" as="xs:string"/>

        <xsl:choose>
            <!-- If input URI already has collection parameters, use it directly -->
            <xsl:when test="contains($provided-uri, '?select=')">
                <xsl:sequence select="$provided-uri"/>
            </xsl:when>
            <!-- If input is a directory URI without parameters, append default collection parameters -->
            <xsl:when test="$provided-uri ne ''">
                <xsl:variable name="base-uri" select="f:as-uri($provided-uri)" as="xs:string"/>
                <xsl:variable name="dir-uri" select="if (ends-with($base-uri, '/')) then $base-uri else $base-uri || '/'" as="xs:string"/>
                <xsl:sequence select="$dir-uri || '?select=*.xml;recurse=yes;on-error=ignore'"/>
            </xsl:when>
            <!-- Default: use base-uri of context document -->
            <xsl:otherwise>
                <xsl:variable name="base-dir-uri" select="replace(string(base-uri($context)), '[^/]+$', '')" as="xs:string"/>
                <xsl:variable name="dir-uri" select="if (ends-with($base-dir-uri, '/')) then $base-dir-uri else $base-dir-uri || '/'" as="xs:string"/>
                <xsl:sequence select="$dir-uri || '?select=*.xml;recurse=no;on-error=ignore'"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <xsl:function name="f:strip-query" as="xs:string">
        <xsl:param name="uri" as="xs:string?"/>
        <xsl:sequence select="replace(normalize-space($uri), '\?.*$', '')"/>
    </xsl:function>

    <xsl:function name="f:parent-dir-uri" as="xs:string">
        <xsl:param name="uri" as="xs:string?"/>
        <xsl:variable name="base" select="replace(f:strip-query($uri), '/+$', '')" as="xs:string"/>
        <xsl:variable name="parent" select="replace($base, '/[^/]*$', '')" as="xs:string"/>
        <xsl:sequence select="if (ends-with($parent, '/')) then $parent else $parent || '/'"/>
    </xsl:function>

    <xsl:function name="f:schema-matches-doc" as="xs:boolean">
        <xsl:param name="doc" as="document-node()"/>
        <xsl:param name="schema-name" as="xs:string?"/>
        <xsl:variable name="schema-lc" select="lower-case(normalize-space($schema-name))" as="xs:string"/>
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

    <xsl:function name="f:safe-collection" as="document-node()*">
        <xsl:param name="uri" as="xs:string"/>
        <xsl:try>
            <xsl:sequence select="collection($uri)"/>
            <xsl:catch errors="*">
                <xsl:sequence select="()"/>
            </xsl:catch>
        </xsl:try>
    </xsl:function>

    <!--~
        Function: f:procedure-containers
        Description: Returns the procedure elements from a document, or the root lineage if no procedures exist.
        Parameters:
            - doc: The document node.
        Returns: A sequence of procedure or lineage elements.
    -->
    <xsl:function name="f:procedure-containers" as="element()*">
        <xsl:param name="doc" as="document-node()"/>
        <xsl:sequence select="if (exists($doc/lineage/procedure))
                              then $doc/lineage/procedure
                              else $doc/lineage"/>
    </xsl:function>

    <xsl:function name="f:view-containers" as="element()*">
        <xsl:param name="doc" as="document-node()"/>
        <xsl:sequence select="$doc/lineage/view"/>
    </xsl:function>

    <!--~
        Function: f:procedure-name
        Description: Gets the name of a procedure, either from the XML or the file name if not explicitly set.
        Parameters:
            - container: The procedure or lineage element.
        Returns: The procedure name as a string.
    -->
    <xsl:function name="f:procedure-name" as="xs:string">
        <xsl:param name="container" as="element()"/>
        <xsl:variable name="explicit-name" select="if ($container/self::procedure) then normalize-space(string($container/@name)) else ''" as="xs:string"/>
        <xsl:variable name="uri" select="string((document-uri(root($container)), base-uri($container))[1])" as="xs:string"/>
        <xsl:sequence select="if ($explicit-name ne '')
                              then $explicit-name
                              else replace(tokenize($uri, '/')[last()], '\.xml$', '')"/>
    </xsl:function>

    <!--~
        Function: f:view-name
        Description: Gets the name of a view from the @name attribute.
        Parameters:
            - view: The view element.
        Returns: The view name as a string.
    -->
    <xsl:function name="f:view-name" as="xs:string">
        <xsl:param name="view" as="element()"/>
        <xsl:sequence select="normalize-space(string($view/@name))"/>
    </xsl:function>

    <!--~
        Function: f:view-sources
        Description: Lists tables that a view depends on (from <from> elements).
        Parameters:
            - view: The view element.
        Returns: A sequence of table names (strings).
    -->
    <xsl:function name="f:view-sources" as="xs:string*">
        <xsl:param name="view" as="element()"/>
        <xsl:sequence select="$view/from/@name ! normalize-space(.)[. ne '']"/>
    </xsl:function>

    <!--~
        Function: f:reads
        Description: Lists tables read by a procedure (from insert, update, merge, delete statements).
        Parameters:
            - container: The procedure or lineage element.
        Returns: A sequence of table names (strings).
    -->
    <xsl:function name="f:reads" as="xs:string*">
        <xsl:param name="container" as="element()"/>
        <xsl:sequence select="$container/*[self::insert or self::update or self::merge or self::delete]/from/@name ! normalize-space(.)[. ne '']"/>
    </xsl:function>

    <!--~
        Function: f:writes
        Description: Lists tables written by a procedure (to insert, update, merge, delete statements).
        Parameters:
            - container: The procedure or lineage element.
        Returns: A sequence of table names (strings).
    -->
    <xsl:function name="f:writes" as="xs:string*">
        <xsl:param name="container" as="element()"/>
        <xsl:sequence select="$container/*[self::insert or self::update or self::merge or self::delete]/to/@name ! normalize-space(.)[. ne '']"/>
    </xsl:function>

    <!--~
        Function: f:effective-rule-path
        Description: (Future use) Resolves the effective rule path for a compressed AST rule node.
        Parameters:
            - rule: The rule element.
        Returns: The effective rule path as a string, or empty if not found.
    -->
    <xsl:function name="f:effective-rule-path" as="xs:string?">
        <xsl:param name="rule" as="element()?"/>

        <xsl:variable name="path-id"
                      select="if (exists($rule) and $rule/@pathId) then normalize-space(string($rule/@pathId)) else ''"
                      as="xs:string"/>

        <xsl:variable name="indexed"
                      select="if ($path-id ne '')
                              then normalize-space(string((root($rule)/ast/pathIndex/path[@id = $path-id]/@value)[1]))
                              else ''"
                      as="xs:string"/>

        <xsl:sequence select="if ($indexed ne '')
                              then $indexed
                              else if (exists($rule))
                              then string-join($rule/ancestor-or-self::*[self::r]/@name ! normalize-space(.), '/')
                              else ()"/>
    </xsl:function>

    <!--~
        Function: f:extract-schema
        Description: Extracts the schema name from a document URI path.
        Parameters:
            - uri: The document URI.
        Returns: The schema name (buss, cons, sdp, dsa) or empty string.
    -->
    <xsl:function name="f:extract-schema" as="xs:string">
        <xsl:param name="uri" as="xs:string"/>
        <xsl:choose>
            <xsl:when test="matches($uri, '/(buss|cons|sdp|dsa)/')">
                <xsl:sequence select="replace($uri, '^.*?/(buss|cons|sdp|dsa)/.*$', '$1')"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="''"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <!--~
        Function: f:called-procedures
        Description: Gets all procedures called by a given procedure, within the same schema.
        Parameters:
            - procedure: The procedure element.
            - schema: The schema name to filter by.
        Returns: A sequence of procedure name strings.
    -->
    <xsl:function name="f:called-procedures" as="xs:string*">
        <xsl:param name="procedure" as="element()"/>
        <xsl:param name="schema" as="xs:string"/>
        <!-- Extract procedure names from call elements, filtering out system schemas like dbms_output, utils, etc. -->
        <xsl:sequence select="$procedure/call[@schema = '' or @schema = $schema]/@procedure ! normalize-space(.)"/>
    </xsl:function>

    <!--~
        Template: match="/"
        Description: Main entry point. Loads all relevant XML files, builds call tree from procedures within same schema.
    -->
    <xsl:template match="/">
        <!-- Extract schema from input-uri parameter -->
        <xsl:variable name="detected-schema" select="f:extract-schema($input-uri)" as="xs:string"/>
        <xsl:variable name="effective-schema" select="if (normalize-space($schema-name)) then $schema-name else $detected-schema" as="xs:string"/>
        <xsl:variable name="primary-uri" select="f:collection-uri(., $input-uri)" as="xs:string"/>
        <xsl:variable name="primary-docs" select="f:safe-collection($primary-uri)" as="document-node()*"/>
        <xsl:variable name="fallback-uri"
                      select="f:parent-dir-uri($input-uri) || '?select=*.xir;recurse=yes;on-error=ignore'"
                      as="xs:string"/>
        <xsl:variable name="resolved-docs"
                      select="if (exists($primary-docs)) then $primary-docs else f:safe-collection($fallback-uri)"
                      as="document-node()*"/>
        <xsl:variable name="docs"
                      select="$resolved-docs[f:schema-matches-doc(., $effective-schema)]"
                      as="document-node()*"/>

        <!-- Extract all procedures from all documents -->
        <xsl:variable name="all-procedures" as="element()*">
            <xsl:for-each select="$docs">
                <xsl:for-each select="lineage/procedure">
                    <xsl:copy>
                        <xsl:copy-of select="@*"/>
                        <xsl:attribute name="__schema" select="$effective-schema"/>
                        <xsl:copy-of select="node()"/>
                    </xsl:copy>
                </xsl:for-each>
            </xsl:for-each>
        </xsl:variable>

        <!-- Find all procedures that are called by someone -->
        <xsl:variable name="called-procs" as="xs:string*">
            <xsl:for-each select="$all-procedures">
                <xsl:variable name="schema" select="@__schema" as="xs:string"/>
                <xsl:sequence select="f:called-procedures(., $schema)"/>
            </xsl:for-each>
        </xsl:variable>

        <!-- Find root procedures (those not called by anyone) -->
        <xsl:variable name="root-procedures" as="element()*">
            <xsl:for-each select="$all-procedures[not(@name = $called-procs)]">
                <xsl:sort select="@name"/>
                <xsl:sequence select="."/>
            </xsl:for-each>
        </xsl:variable>

        <calls schema="{$effective-schema}">
            <xsl:for-each select="$root-procedures">
                <xsl:call-template name="build-call-tree">
                    <xsl:with-param name="procedure" select="."/>
                    <xsl:with-param name="all-procedures" select="$all-procedures"/>
                    <xsl:with-param name="schema" select="$effective-schema"/>
                </xsl:call-template>
            </xsl:for-each>
        </calls>
    </xsl:template>

    <!--~
        Template: name="build-call-tree"
        Description: Recursively builds the call tree for a procedure and its callees.
        Parameters:
            - procedure: The procedure element to process.
            - all-procedures: All procedures in scope.
            - schema: The schema name.
    -->
    <xsl:template name="build-call-tree">
        <xsl:param name="procedure" as="element()"/>
        <xsl:param name="all-procedures" as="element()*"/>
        <xsl:param name="schema" as="xs:string"/>

        <xsl:variable name="proc-name" select="normalize-space($procedure/@name)" as="xs:string"/>
        <xsl:variable name="called-proc-names" select="f:called-procedures($procedure, $schema)" as="xs:string*"/>

        <call name="{$proc-name}">
            <!-- Recursively build trees for each called procedure -->
            <xsl:for-each select="$all-procedures[@__schema = $schema][@name = $called-proc-names]">
                <xsl:sort select="@name"/>
                <xsl:call-template name="build-call-tree">
                    <xsl:with-param name="procedure" select="."/>
                    <xsl:with-param name="all-procedures" select="$all-procedures"/>
                    <xsl:with-param name="schema" select="$schema"/>
                </xsl:call-template>
            </xsl:for-each>
        </call>
    </xsl:template>

</xsl:stylesheet>
