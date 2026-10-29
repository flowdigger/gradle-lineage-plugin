<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:f="urn:lineage-fn"
                exclude-result-prefixes="f xs"
                expand-text="yes">

    <!--~
        Output: XML
        Indents output for readability.
    -->
    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-skip"/>

    <!-- Normalize token text and remove delimiter quotes for DELIMITED_ID identifiers. -->
    <xsl:function name="f:token-value" as="xs:string">
        <xsl:param name="token" as="element(t)?"/>
        <xsl:variable name="raw" select="normalize-space(string($token))" as="xs:string"/>
        <xsl:sequence select="if (exists($token) and $token/@type = 'DELIMITED_ID')
                              then replace(replace($raw, '^&quot;(.*)&quot;$', '$1'), '&quot;&quot;', '&quot;')
                              else $raw"/>
    </xsl:function>

    <!--~
        Template: match="/ast"
        Description: Entry point. Processes the root AST node and emits a <lineage> element
        containing <procedure> elements for each detected procedure.
    -->
    <xsl:template match="/ast">
        <lineage>
            <xsl:copy-of select="@*"/>
            <xsl:for-each select=".//r[@name='unit_statement'][descendant::r[@name='procedure_name']]">
                <procedure name="{f:procedure-name(.)}">
                    <xsl:apply-templates select=".//r[@name='body'][1]//r[@name='statement']" mode="emit-lineage"/>
                </procedure>
            </xsl:for-each>
            <xsl:for-each select=".//r[@name='create_package_body'][descendant::r[@name='package_name']]">
                <package name="{r[@name='package_name'][1]//t[not(@type = 'PERIOD')] ! f:token-value(.)}">

                    <xsl:for-each select=".//r[@name='procedure_body'][1]">
                        <procedure name="{r[@name='identifier'][1]//t[not(@type = 'PERIOD')] ! f:token-value(.)}">
                            <xsl:apply-templates select=".//r[@name='statement']" mode="emit-lineage"/>
                        </procedure>
                    </xsl:for-each>
<!--                    <xsl:apply-templates select=".//r[@name='procedure_body'][1]//r[@name='statement']" mode="emit-lineage"/>-->

                </package>
            </xsl:for-each>
            <xsl:for-each select=".//r[@name='unit_statement'][r[@name='create_view']]">
                <xsl:variable name="create-view" select="r[@name='create_view'][1]" as="element(r)"/>
                <xsl:variable name="view-name-node" select="$create-view/r[@name='view_name'][1]" as="element(r)?"/>
                <view name="{f:table-name($view-name-node)}"
                      line="{f:node-line(($view-name-node, $create-view)[1])}"
                      column="{f:node-column(($view-name-node, $create-view)[1])}">
                    <xsl:for-each-group select="f:source-table-nodes($create-view, $view-name-node)" group-by="f:table-name(.)">
                        <xsl:if test="normalize-space(current-grouping-key())">
                            <from name="{current-grouping-key()}"/>
                        </xsl:if>
                    </xsl:for-each-group>
                </view>
            </xsl:for-each>
        </lineage>
    </xsl:template>

    <!--~
        Template: match="@*|node()" mode="emit-lineage"
        Description: Default template for emit-lineage mode. Skips nodes that are not specifically handled.
    -->
    <xsl:template match="@*|node()" mode="emit-lineage"/>

    <!--~
        Template: match="r[@name='statement']" mode="emit-lineage"
        Description: Processes a statement node and emits the corresponding lineage element
        (call, insert, update, merge, delete) based on the statement type.
    -->
    <xsl:template match="r[@name='statement']" mode="emit-lineage">
        <xsl:choose>
            <xsl:when test="f:is-call-statement(.)">
                <xsl:variable name="parts" select="(r[@name='call_statement']/r[@name='routine_name'], .//r[@name='routine_name'][1])[1]//t[not(@type = 'PERIOD')] ! f:token-value(.)" as="xs:string*"/>
                <call line="{f:statement-line(.)}"
                      procedure="{if (exists($parts)) then $parts[last()] else ''}"
                      schema="{if (count($parts) gt 1) then string-join($parts[position() lt last()], '.') else ''}"/>
            </xsl:when>
            <xsl:when test="f:is-insert-statement(.)">
                <xsl:variable name="target" select="(r[@name='insert_statement']//r[@name='insert_into_clause']/r[@name='general_table_ref'])[1]" as="element(r)?"/>
                <xsl:call-template name="emit-dml-lineage">
                    <xsl:with-param name="tag" select="'insert'"/>
                    <xsl:with-param name="statement" select="."/>
                    <xsl:with-param name="target" select="$target"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:when test="f:is-update-statement(.)">
                <xsl:variable name="target" select="(r[@name='update_statement']//r[@name='general_table_ref'])[1]" as="element(r)?"/>
                <xsl:call-template name="emit-dml-lineage">
                    <xsl:with-param name="tag" select="'update'"/>
                    <xsl:with-param name="statement" select="."/>
                    <xsl:with-param name="target" select="$target"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:when test="f:is-merge-statement(.)">
                <!-- MERGE target: first try merge_target, then fallback to general_table_ref etc. -->
                <xsl:variable name="target"
                              select="(r[@name='merge_statement']/r[@name='merge_target'][1],
                                       r[@name='merge_statement']//r[@name='merge_into_clause']//r[@name=('general_table_ref', 'tableview_name', 'table_ref_aux_internal')][1],
                                       r[@name='merge_statement']//r[@name=('general_table_ref', 'tableview_name', 'table_ref_aux_internal')][1])[1]"
                              as="element(r)?"/>
                <xsl:call-template name="emit-dml-lineage">
                    <xsl:with-param name="tag" select="'merge'"/>
                    <xsl:with-param name="statement" select="."/>
                    <xsl:with-param name="target" select="$target"/>
                </xsl:call-template>
            </xsl:when>
            <xsl:when test="f:is-delete-statement(.)">
                <xsl:variable name="target" select="(r[@name='delete_statement']//r[@name='general_table_ref'])[1]" as="element(r)?"/>
                <xsl:call-template name="emit-dml-lineage">
                    <xsl:with-param name="tag" select="'delete'"/>
                    <xsl:with-param name="statement" select="."/>
                    <xsl:with-param name="target" select="$target"/>
                </xsl:call-template>
            </xsl:when>
        </xsl:choose>
    </xsl:template>

    <!--~
        Template: name="emit-dml-lineage"
        Description: Emits a DML lineage element (insert, update, merge, delete) with target and source tables.
        Parameters:
            - tag: The DML operation (insert, update, merge, delete).
            - statement: The statement node.
            - target: The target table node.
    -->
    <xsl:template name="emit-dml-lineage">
        <xsl:param name="tag" as="xs:string"/>
        <xsl:param name="statement" as="element(r)"/>
        <xsl:param name="target" as="element(r)?"/>

        <xsl:element name="{$tag}">
            <xsl:attribute name="line" select="f:statement-line($statement)"/>
            <to name="{f:table-name($target)}"/>
            <xsl:for-each-group select="f:source-table-nodes($statement, $target)" group-by="f:table-name(.)">
                <xsl:if test="normalize-space(current-grouping-key())">
                    <from name="{current-grouping-key()}"/>
                </xsl:if>
            </xsl:for-each-group>
        </xsl:element>
    </xsl:template>

    <!--~
        Function: f:table-name
        Description: Extracts and normalizes a table name from a node, filtering out SQL keywords and complex expressions.
        Parameters:
            - node: The AST node representing a table reference.
        Returns: The lower-case table name, or an empty string if not a valid table name.
    -->
    <xsl:function name="f:table-name" as="xs:string">
        <xsl:param name="node" as="element()?"/>
        <xsl:variable name="raw-name" as="xs:string">
            <xsl:choose>
                <xsl:when test="$node/self::t[@type=('REGULAR_ID', 'DELIMITED_ID')]">
                    <xsl:sequence select="f:token-value($node)"/>
                </xsl:when>
                <xsl:when test="exists($node)">
                    <xsl:sequence select="normalize-space(string-join($node//t[not(@type = ('LEFT_PAREN', 'RIGHT_PAREN'))] ! f:token-value(.), ''))"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:sequence select="''"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <!-- Only return the name if it doesn't contain SQL keywords (filter out embedded queries) -->
        <!-- JH: made lowercase. -->
        <xsl:sequence select="if (f:has-sql-keywords($raw-name)) then '' else lower-case($raw-name)"/>
    </xsl:function>

    <!--~
        Function: f:procedure-name
        Description: Extracts the procedure or function name from a unit_statement node.
        Parameters:
            - unit: The AST node representing the procedure or function.
        Returns: The normalized, lower-case name as a string.
    -->
    <xsl:function name="f:procedure-name" as="xs:string">
        <xsl:param name="unit" as="element(r)"/>
        <xsl:variable name="procedure-parts"
                      select="$unit//r[@name='procedure_name'][1]//t[not(@type = 'PERIOD')] ! f:token-value(.)"
                      as="xs:string*"/>
        <xsl:variable name="function-parts"
                      select="$unit//r[@name='function_name'][1]//t[not(@type = 'PERIOD')] ! f:token-value(.)"
                      as="xs:string*"/>
        <xsl:variable name="parts"
                      select="if (exists($procedure-parts)) then $procedure-parts else $function-parts"
                      as="xs:string*"/>
        <!-- JH: made lower case -->
        <xsl:sequence select="lower-case(string-join($parts, '.'))"/>
    </xsl:function>

    <!--~
        Function: f:path-value
        Description: Resolves the path value for a node using the pathIndex if available.
        Parameters:
            - node: The AST node.
        Returns: The resolved path as a string, or empty if not found.
    -->
    <xsl:function name="f:path-value" as="xs:string">
        <xsl:param name="node" as="element()?"/>
        <xsl:variable name="owner" select="$node/ancestor-or-self::r[@pathId][1]" as="element(r)?"/>
        <xsl:sequence select="if (exists($owner))
                              then string((root($owner)/ast/pathIndex/path[@id = $owner/@pathId]/@value)[1])
                              else ''"/>
    </xsl:function>

    <!--~
        Function: f:statement-line
        Description: Extracts the line number from a statement node.
        Parameters:
            - statement: The statement node.
        Returns: The line number as a string, or empty if not found.
    -->
    <xsl:function name="f:statement-line" as="xs:string">
        <xsl:param name="statement" as="element(r)"/>
        <xsl:sequence select="string(($statement//t[@line][1]/@line, '')[1])"/>
    </xsl:function>

    <!--~
        Function: f:node-line
        Description: Extracts the first available line number from any node.
        Parameters:
            - node: The node to inspect.
        Returns: The line number as a string, or empty if not found.
    -->
    <xsl:function name="f:node-line" as="xs:string">
        <xsl:param name="node" as="element()?"/>
        <xsl:sequence select="string(($node//t[@line][1]/@line, '')[1])"/>
    </xsl:function>

    <!--~
        Function: f:node-column
        Description: Extracts the first available column number from any node.
        Parameters:
            - node: The node to inspect.
        Returns: The column number as a string, or empty if not found.
    -->
    <xsl:function name="f:node-column" as="xs:string">
        <xsl:param name="node" as="element()?"/>
        <xsl:sequence select="string(($node//t[@column][1]/@column, '')[1])"/>
    </xsl:function>

    <!--~
        Function: f:is-call-statement
        Description: Determines if a statement node represents a CALL statement.
        Parameters:
            - statement: The statement node.
        Returns: true if it is a call statement, false otherwise.
    -->
    <xsl:function name="f:is-call-statement" as="xs:boolean">
        <xsl:param name="statement" as="element(r)"/>
        <xsl:sequence select="exists($statement/r[@name='call_statement'])
                              or contains(lower-case(f:path-value($statement)), 'call_statement')"/>
    </xsl:function>

    <!--~
        Function: f:is-insert-statement
        Description: Determines if a statement node represents an INSERT statement.
        Parameters:
            - statement: The statement node.
        Returns: true if it is an insert statement, false otherwise.
    -->
    <xsl:function name="f:is-insert-statement" as="xs:boolean">
        <xsl:param name="statement" as="element(r)"/>
        <xsl:sequence select="exists($statement/r[@name='insert_statement'])
                              or contains(lower-case(f:path-value($statement)), 'insert_statement')"/>
    </xsl:function>

    <!--~
        Function: f:is-update-statement
        Description: Determines if a statement node represents an UPDATE statement.
        Parameters:
            - statement: The statement node.
        Returns: true if it is an update statement, false otherwise.
    -->
    <xsl:function name="f:is-update-statement" as="xs:boolean">
        <xsl:param name="statement" as="element(r)"/>
        <xsl:sequence select="exists($statement/r[@name='update_statement'])
                              or contains(lower-case(f:path-value($statement)), 'update_statement')"/>
    </xsl:function>

    <!--~
        Function: f:is-delete-statement
        Description: Determines if a statement node represents a DELETE statement.
        Parameters:
            - statement: The statement node.
        Returns: true if it is a delete statement, false otherwise.
    -->
    <xsl:function name="f:is-delete-statement" as="xs:boolean">
        <xsl:param name="statement" as="element(r)"/>
        <xsl:sequence select="exists($statement/r[@name='delete_statement'])
                              or contains(lower-case(f:path-value($statement)), 'delete_statement')"/>
    </xsl:function>

    <!--~
        Function: f:is-merge-statement
        Description: Determines if a statement node represents a MERGE statement.
        Parameters:
            - statement: The statement node.
        Returns: true if it is a merge statement, false otherwise.
    -->
    <xsl:function name="f:is-merge-statement" as="xs:boolean">
        <xsl:param name="statement" as="element(r)"/>
        <xsl:sequence select="exists($statement/r[@name='merge_statement'])
                              or contains(lower-case(f:path-value($statement)), 'merge_statement')"/>
    </xsl:function>

    <!--~
        Function: f:is-table-reference
        Description: Determines if a node is a table reference node.
        Parameters:
            - node: The AST node.
        Returns: true if it is a table reference, false otherwise.
    -->
    <xsl:function name="f:is-table-reference" as="xs:boolean">
        <xsl:param name="node" as="element(r)"/>
        <xsl:variable name="path" select="lower-case(f:path-value($node))" as="xs:string"/>
        <xsl:sequence select="$node/@name = ('tableview_name', 'general_table_ref', 'table_ref_aux_internal')
                              or contains($path, 'tableview_name')
                              or contains($path, 'table_ref_aux_internal')
                              or contains($path, 'general_table_ref/dml_table_expression_clause/tableview_name')"/>
    </xsl:function>

    <!--~
        Function: f:is-simple-table-name
        Description: Checks if a string is a simple table name (not a SQL keyword or complex expression).
        Parameters:
            - name: The table name string.
        Returns: true if it is a simple table name, false otherwise.
    -->
    <xsl:function name="f:is-simple-table-name" as="xs:boolean">
        <xsl:param name="name" as="xs:string"/>
        <!-- Reject names containing SQL keywords or complex expressions -->
        <xsl:sequence select="not(matches($name, '^\s*$'))
                              and not(matches($name, '(SELECT|FROM|WHERE|UNION|JOIN|GROUP|ORDER|CASE|WHEN|THEN|ELSE|SUBQUERY)', 'i'))
                              and not(contains($name, '||'))
                              and not(contains($name, '('))
                              and not(contains($name, 'COUNT'))
                              and not(contains($name, 'SUM'))
                              and not(contains($name, 'MAX'))
                              and not(contains($name, 'MIN'))
                              and string-length($name) lt 128"/>
    </xsl:function>

    <!--~
        Function: f:is-simple-table-node
        Description: Checks if a node is a simple table node (not deeply nested or complex).
        Parameters:
            - node: The AST node.
        Returns: true if it is a simple table node, false otherwise.
    -->
    <xsl:function name="f:is-simple-table-node" as="xs:boolean">
        <xsl:param name="node" as="element(r)"/>
        <!-- Only accept nodes with simple structure (few descendants), not deeply nested expressions -->
        <xsl:variable name="desc-count" select="count($node//r)" as="xs:integer"/>
        <xsl:variable name="path" select="lower-case(f:path-value($node))" as="xs:string"/>
        <!-- Accept if resolved path explicitly mentions tableview_name or simple structure -->
        <xsl:sequence select="(contains($path, 'tableview_name')
                               or contains($path, 'table_ref_aux_internal/identifier'))
                              and $desc-count lt 10"/>
    </xsl:function>

    <!--~
        Function: f:has-sql-keywords
        Description: Checks if a string contains SQL keywords, indicating it is not a simple table name.
        Parameters:
            - text: The string to check.
        Returns: true if it contains SQL keywords, false otherwise.
    -->
    <xsl:function name="f:has-sql-keywords" as="xs:boolean">
        <xsl:param name="text" as="xs:string?"/>
        <!-- Check if text contains SQL operations indicating it's not a simple table name -->
        <xsl:sequence select="matches($text, '(SELECT|FROM|WHERE|UNION|CASE|COUNT|SUM|JOIN|INNER|LEFT|RIGHT)', 'i')"/>
    </xsl:function>

    <!--~
        Function: f:source-table-nodes
        Description: Identifies all source table nodes referenced in a statement, excluding the target table.
        Parameters:
            - statement: The statement node.
            - target: The target table node.
        Returns: A sequence of source table nodes.
    -->
    <xsl:function name="f:source-table-nodes" as="element()*">
        <xsl:param name="statement" as="element(r)"/>
        <xsl:param name="target" as="element(r)?"/>

        <!-- Collect ONLY explicit tableview_name nodes - these must have simple names without SQL keywords. -->
        <xsl:variable name="explicit_tableview"
                      select="$statement//r[@name='tableview_name']
                                          [not(f:has-sql-keywords(f:table-name(.)))]"
                      as="element(r)*"/>

        <!-- Bare REGULAR_ID tokens from table_ref_list (e.g. FROM DUAL) with simple names.  -->
        <xsl:variable name="bare_table_tokens"
                      select="$statement//(r[@name='table_ref_list'] | r[@name='table_ref']/r[@name='table_ref_list'])/
                              t[@type='REGULAR_ID'][not(f:has-sql-keywords(normalize-space(.)))]"
                      as="element(t)*"/>

        <!-- Carefully select table_ref_aux_internal nodes resolved via pathIndex to simple table names. -->
        <xsl:variable name="table_ref_internal"
                      select="$statement//r[@name='table_ref_aux_internal']
                                          [f:is-simple-table-node(.)]
                                          [not(f:has-sql-keywords(f:table-name(.)))]"
                      as="element(r)*"/>

        <!-- Distinct table references by name to avoid duplicates. -->
        <xsl:sequence select="($explicit_tableview, $table_ref_internal, $bare_table_tokens)
                              [normalize-space(f:table-name(.))]
                              [not(. is $target)]
                              [not(lower-case(f:table-name(.)) = lower-case(f:table-name($target)))]
                              [not(ancestor::r[@name='insert_into_clause' or @name='merge_into_clause'])]
                              [not(ancestor::r[@name='general_table_ref' and parent::r[@name='delete_statement' or @name='update_statement']])]"/>
    </xsl:function>
</xsl:stylesheet>